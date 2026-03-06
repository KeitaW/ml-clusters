#!/usr/bin/env python3
"""Automated MobilityGen synthetic data generation pipeline.

Runs Isaac Sim headless to generate RGB, depth, and segmentation data
from randomized robot trajectories in a warehouse environment.

Usage (inside Isaac Sim container):
    /isaac-sim/python.sh /isaac-sim/scripts/automated_mobilitygen.py \
        --num_trajectories 5 --num_frames 100 --output_dir /output
"""

import argparse
import functools
import os
import sys

# Isaac Sim buffers stdout; ensure all prints are flushed for K8s log visibility
print = functools.partial(print, flush=True)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Automated MobilityGen SDG pipeline"
    )
    parser.add_argument(
        "--num_trajectories",
        type=int,
        default=5,
        help="Number of random trajectories to generate",
    )
    parser.add_argument(
        "--num_frames",
        type=int,
        default=100,
        help="Number of frames to capture per trajectory",
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="/output",
        help="Directory to save generated data",
    )
    parser.add_argument(
        "--scene",
        type=str,
        default="omniverse://localhost/NVIDIA/Assets/Isaac/4.2/Isaac/Environments/Simple_Warehouse/full_warehouse.usd",
        help="USD scene path to load",
    )
    parser.add_argument(
        "--image_width",
        type=int,
        default=640,
        help="Output image width",
    )
    parser.add_argument(
        "--image_height",
        type=int,
        default=480,
        help="Output image height",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        default=True,
        help="Run in headless mode (default: True)",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    # Delayed imports — these only work inside the Isaac Sim Python environment
    from isaacsim import SimulationApp

    config = {
        "headless": args.headless,
        "width": args.image_width,
        "height": args.image_height,
    }
    simulation_app = SimulationApp(config)

    import numpy as np
    import omni.replicator.core as rep
    import omni.usd

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"[MobilityGen] Creating new stage")

    # Create a fresh stage with a warehouse-like environment
    omni.usd.get_context().new_stage()
    rep.orchestrator.set_capture_on_play(False)

    import carb.settings
    carb.settings.get_settings().set("rtx/post/dlss/execMode", 2)

    from pxr import Sdf, UsdGeom

    stage = omni.usd.get_context().get_stage()
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)

    # Create environment: ground plane, lights, obstacles
    ground = stage.DefinePrim("/World/Ground", "Cube")
    UsdGeom.Xformable(ground).AddTranslateOp().Set((0, 0, -0.5))
    UsdGeom.Xformable(ground).AddScaleOp().Set((50, 50, 0.5))

    dome_light = stage.DefinePrim("/World/DomeLight", "DomeLight")
    dome_light.CreateAttribute("inputs:intensity", Sdf.ValueTypeNames.Float).Set(500.0)

    # Create some obstacle cubes for visual variety
    for i in range(5):
        box = stage.DefinePrim(f"/World/Obstacle_{i}", "Cube")
        UsdGeom.Xformable(box).AddTranslateOp().Set((i * 2.0, 3.0, 0.5))
        UsdGeom.Xformable(box).AddScaleOp().Set((0.5, 0.5, 1.0))

    from isaacsim.core.utils.semantics import add_labels
    add_labels(ground, labels=["Floor"], instance_name="class")
    for i in range(5):
        box = stage.GetPrimAtPath(f"/World/Obstacle_{i}")
        add_labels(box, labels=["Obstacle"], instance_name="class")

    # Set up Replicator writer for RGB, depth, and semantic segmentation
    writer = rep.writers.get("BasicWriter")
    writer.initialize(
        output_dir=args.output_dir,
        rgb=True,
        distance_to_image_plane=True,
        semantic_segmentation=True,
    )

    # Create a camera for data capture
    camera = rep.create.camera(
        position=(0, 2, 1),
        look_at=(5, 2, 0),
    )

    render_product = rep.create.render_product(
        camera, (args.image_width, args.image_height)
    )
    writer.attach([render_product])

    total_frames = 0

    for traj_idx in range(args.num_trajectories):
        print(
            f"[MobilityGen] Trajectory {traj_idx + 1}/{args.num_trajectories}"
        )

        # Randomize camera position along a path through the scene
        # Simulate a robot traversing the warehouse
        for frame_idx in range(args.num_frames):
            # Move camera along a randomized path
            t = frame_idx / max(args.num_frames - 1, 1)
            x = t * 10.0 + np.random.normal(0, 0.1)
            y = 2.0 + np.random.normal(0, 0.05)
            z = 1.0

            look_x = x + 2.0
            look_y = y + np.random.normal(0, 0.1)
            look_z = 0.5

            with rep.trigger.on_frame():
                with camera:
                    rep.modify.pose(
                        position=(x, y, z),
                        look_at=(look_x, look_y, look_z),
                    )

            rep.orchestrator.step()
            total_frames += 1

        print(
            f"[MobilityGen] Trajectory {traj_idx + 1} complete: "
            f"{args.num_frames} frames captured"
        )

    print(
        f"[MobilityGen] Pipeline complete. "
        f"Total frames: {total_frames}, output: {args.output_dir}"
    )

    # List output files
    for root, dirs, files in os.walk(args.output_dir):
        for f in files:
            fpath = os.path.join(root, f)
            size_mb = os.path.getsize(fpath) / (1024 * 1024)
            print(f"  {fpath} ({size_mb:.1f} MB)")

    simulation_app.close()
    print("[MobilityGen] Done.")


if __name__ == "__main__":
    main()
