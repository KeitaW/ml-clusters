#!/usr/bin/env python3
"""Stage 2: Occupancy Map Generation.

Downloads the warehouse USD scene from S3, computes a 2D occupancy grid
via top-down orthographic depth render, and uploads the result.

Usage (inside Isaac Sim container):
    /isaac-sim/python.sh /isaac-sim/scripts/stage2_occupancy_map.py \
        --s3_bucket my-bucket --run_id run-001
"""

import argparse
import functools
import json
import os
import sys

print = functools.partial(print, flush=True)


def parse_args():
    parser = argparse.ArgumentParser(description="Stage 2: Occupancy Map Generation")
    parser.add_argument("--s3_bucket", type=str, required=True)
    parser.add_argument("--run_id", type=str, required=True)
    parser.add_argument("--output_dir", type=str, default="/output/occupancy")
    parser.add_argument("--scene_dir", type=str, default="/input/scene")
    parser.add_argument("--resolution", type=float, default=0.1, help="Grid resolution in meters/pixel")
    parser.add_argument("--depth_threshold", type=float, default=0.5, help="Depth threshold for obstacle detection")
    parser.add_argument("--headless", action="store_true", default=True)
    return parser.parse_args()


def main():
    args = parse_args()
    print("[Stage2] Starting occupancy map generation")

    # Download scene from S3
    scripts_dir = os.path.dirname(os.path.abspath(__file__))
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)

    from utils.s3_sync import download_directory, upload_directory, make_stage_path

    scene_s3 = make_stage_path(args.s3_bucket, args.run_id, "scene")
    print(f"[Stage2] Downloading scene from {scene_s3}")
    download_directory(scene_s3, args.scene_dir)

    usd_path = os.path.join(args.scene_dir, "warehouse_scene.usd")
    meta_path = os.path.join(args.scene_dir, "metadata.json")

    with open(meta_path) as f:
        scene_meta = json.load(f)

    from isaacsim import SimulationApp
    simulation_app = SimulationApp({"headless": args.headless, "width": 1024, "height": 1024})

    import numpy as np
    import omni.replicator.core as rep
    import omni.usd
    import carb.settings

    carb.settings.get_settings().set("rtx/post/dlss/execMode", 2)

    print(f"[Stage2] Opening scene: {usd_path}")
    omni.usd.get_context().open_stage(usd_path)

    # Wait for stage to load
    import asyncio
    asyncio.get_event_loop().run_until_complete(omni.usd.get_context().load_stage_async())

    stage = omni.usd.get_context().get_stage()

    # Compute scene bounds for camera placement
    aisle_length = scene_meta.get("aisle_length", 20.0)
    num_aisles = scene_meta.get("num_aisles", 4)
    aisle_width = 3.0
    shelf_depth = 1.0
    total_width = num_aisles * (aisle_width + shelf_depth * 2)

    center_x = aisle_length / 2
    center_y = (num_aisles - 1) * (aisle_width + shelf_depth * 2) / 2

    # Determine render size to match resolution
    scene_extent_x = aisle_length + 4
    scene_extent_y = total_width + 4
    render_width = int(scene_extent_x / args.resolution)
    render_height = int(scene_extent_y / args.resolution)
    # Clamp to reasonable size
    render_width = min(render_width, 2048)
    render_height = min(render_height, 2048)

    print(f"[Stage2] Render size: {render_width}x{render_height}, resolution: {args.resolution} m/px")

    # Create overhead orthographic camera
    from pxr import Gf, UsdGeom

    cam_prim = stage.DefinePrim("/World/OccupancyCamera", "Camera")
    cam = UsdGeom.Camera(cam_prim)
    cam.GetProjectionAttr().Set("orthographic")
    cam.GetHorizontalApertureAttr().Set(float(scene_extent_x * 10))  # cm
    cam.GetVerticalApertureAttr().Set(float(scene_extent_y * 10))
    cam.GetClippingRangeAttr().Set(Gf.Vec2f(0.1, 50.0))

    xf = UsdGeom.Xformable(cam_prim)
    xf.AddTranslateOp().Set(Gf.Vec3d(center_x, center_y, 20.0))
    # Look straight down: rotate -90 around X
    xf.AddRotateXYZOp().Set(Gf.Vec3f(0, 0, 0))  # Camera default looks down -Z in ortho

    rep.orchestrator.set_capture_on_play(False)

    # Render depth from overhead
    render_product = rep.create.render_product(
        str(cam_prim.GetPath()), (render_width, render_height)
    )

    writer = rep.writers.get("BasicWriter")
    tmp_render_dir = "/tmp/occupancy_render"
    os.makedirs(tmp_render_dir, exist_ok=True)
    writer.initialize(
        output_dir=tmp_render_dir,
        rgb=False,
        distance_to_image_plane=True,
        semantic_segmentation=False,
    )
    writer.attach([render_product])

    # Render a single frame
    with rep.trigger.on_frame():
        pass
    rep.orchestrator.step()
    rep.orchestrator.wait_until_complete()

    writer.detach()

    # Load rendered depth and threshold to binary occupancy
    depth_dir = os.path.join(tmp_render_dir, "distance_to_image_plane")
    depth_files = [f for f in os.listdir(depth_dir) if f.endswith(".npy")]
    if not depth_files:
        print("[Stage2] ERROR: No depth render output found")
        simulation_app.close()
        sys.exit(1)

    depth_map = np.load(os.path.join(depth_dir, depth_files[0]))
    if depth_map.ndim == 3:
        depth_map = depth_map[:, :, 0]

    print(f"[Stage2] Depth map shape: {depth_map.shape}, range: [{depth_map.min():.2f}, {depth_map.max():.2f}]")

    # Objects closer to camera (lower depth at top-down view) are obstacles
    # Floor is at z=0, camera at z=20, so floor depth ~20, obstacles < 20
    max_depth = depth_map.max()
    # Occupied = where depth is significantly less than max (obstacle present)
    occupancy = np.zeros_like(depth_map, dtype=np.uint8)
    obstacle_mask = depth_map < (max_depth - args.depth_threshold)
    occupancy[obstacle_mask] = 1  # 1 = occupied, 0 = free

    print(f"[Stage2] Occupancy: {occupancy.sum()} occupied cells, "
          f"{(occupancy == 0).sum()} free cells out of {occupancy.size} total")

    os.makedirs(args.output_dir, exist_ok=True)

    # Save occupancy grid
    np.save(os.path.join(args.output_dir, "occupancy_map.npy"), occupancy)

    # Save visualization PNG
    from PIL import Image
    vis = np.zeros((*occupancy.shape, 3), dtype=np.uint8)
    vis[occupancy == 0] = [255, 255, 255]  # Free = white
    vis[occupancy == 1] = [0, 0, 0]        # Occupied = black
    Image.fromarray(vis).save(os.path.join(args.output_dir, "occupancy_map.png"))

    # Save metadata
    occ_metadata = {
        "width": occupancy.shape[1],
        "height": occupancy.shape[0],
        "resolution": args.resolution,
        "origin_x": center_x - scene_extent_x / 2,
        "origin_y": center_y - scene_extent_y / 2,
        "occupied_cells": int(occupancy.sum()),
        "free_cells": int((occupancy == 0).sum()),
    }
    with open(os.path.join(args.output_dir, "metadata.json"), "w") as f:
        json.dump(occ_metadata, f, indent=2)

    # Upload to S3
    s3_path = make_stage_path(args.s3_bucket, args.run_id, "occupancy")
    print(f"[Stage2] Uploading to {s3_path}")
    upload_directory(args.output_dir, s3_path)

    simulation_app.close()
    print("[Stage2] Done.")


if __name__ == "__main__":
    main()
