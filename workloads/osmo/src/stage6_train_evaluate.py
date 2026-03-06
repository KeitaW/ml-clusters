#!/usr/bin/env python3
"""Stage 6: Baseline Waypoint Regressor — Training + Evaluation.

Downloads raw-v1/, augmented-v2/, and trajectory data from S3, trains a
ResNet18-based waypoint regressor using trajectory-derived labels, and
compares raw-only vs raw+augmented training. This is a baseline downstream
task for validating the synthetic data pipeline — it is NOT a full
X-Mobility or production navigation model.

Usage:
    python /scripts/stage6_train_evaluate.py \
        --s3_bucket my-bucket --run_id run-001
"""

import argparse
import functools
import json
import math
import os
import sys

print = functools.partial(print, flush=True)

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset, Subset
from torchvision import models, transforms


def parse_args():
    parser = argparse.ArgumentParser(description="Stage 6: Baseline Waypoint Regressor")
    parser.add_argument("--s3_bucket", type=str, required=True)
    parser.add_argument("--run_id", type=str, required=True)
    parser.add_argument("--raw_dir", type=str, default="/input/raw-v1")
    parser.add_argument("--aug_dir", type=str, default="/input/augmented-v2")
    parser.add_argument("--traj_dir", type=str, default="/input/trajectories")
    parser.add_argument("--output_dir", type=str, default="/output/results")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch_size", type=int, default=16)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--eval_split", type=float, default=0.2,
                        help="Fraction of data held out for evaluation")
    return parser.parse_args()


def load_trajectory_labels(traj_dir):
    """Load waypoint labels from trajectory JSONs.

    Returns a list of (dx, dy) offsets ordered by frame rendering order
    (trajectory_0000 frames first, then trajectory_0001, etc.).
    """
    traj_files = sorted([
        f for f in os.listdir(traj_dir)
        if f.startswith("trajectory_") and f.endswith(".json")
    ])

    labels = []
    for traj_file in traj_files:
        with open(os.path.join(traj_dir, traj_file)) as f:
            trajectory = json.load(f)

        frames = trajectory["frames"]
        for i, frame in enumerate(frames):
            pos = frame["position"]
            if i < len(frames) - 1:
                next_pos = frames[i + 1]["position"]
                dx = next_pos[0] - pos[0]
                dy = next_pos[1] - pos[1]
            else:
                # Last frame: use previous offset
                dx = labels[-1][0] if labels else 0.0
                dy = labels[-1][1] if labels else 0.0
            labels.append((dx, dy))

    return labels


def find_rgb_files(data_dir):
    """Find RGB image files, handling both flat and subdirectory layouts.

    Flat layout (BasicWriter): rgb_XXXX.png in data_dir root
    Subdirectory layout (CosmosWriter): data_dir/rgb/frame_XXXXXX.png
    """
    rgb_subdir = os.path.join(data_dir, "rgb")
    if os.path.isdir(rgb_subdir):
        return sorted([
            os.path.join(rgb_subdir, f) for f in os.listdir(rgb_subdir)
            if f.lower().endswith((".png", ".jpg", ".jpeg"))
        ])
    # Flat layout: rgb_XXXX.png in root
    return sorted([
        os.path.join(data_dir, f) for f in os.listdir(data_dir)
        if f.startswith("rgb_") and f.lower().endswith((".png", ".jpg", ".jpeg"))
    ])


class NavigationDataset(Dataset):
    """Dataset of RGB frames with trajectory-derived waypoint labels."""

    def __init__(self, data_dirs, waypoint_labels=None, transform=None):
        self.samples = []
        self.transform = transform or transforms.Compose([
            transforms.ToPILImage(),
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406],
                                 std=[0.229, 0.224, 0.225]),
        ])

        for data_dir in data_dirs:
            if not os.path.exists(data_dir):
                continue
            files = find_rgb_files(data_dir)
            for i, fpath in enumerate(files):
                if waypoint_labels is not None and i < len(waypoint_labels):
                    label = list(waypoint_labels[i])
                else:
                    label = [0.0, 0.0]
                self.samples.append((fpath, label))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        img_path, waypoint = self.samples[idx]
        from PIL import Image
        img = np.array(Image.open(img_path).convert("RGB"))
        img = self.transform(img)
        return img, torch.tensor(waypoint, dtype=torch.float32)


class WaypointNavigator(nn.Module):
    """ResNet18 backbone + FC head for waypoint offset prediction (baseline)."""

    def __init__(self):
        super().__init__()
        backbone = models.resnet18(weights=None)
        self.features = nn.Sequential(*list(backbone.children())[:-1])
        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(512, 128),
            nn.ReLU(),
            nn.Linear(128, 2),  # (dx, dy) offset
        )

    def forward(self, x):
        feat = self.features(x)
        return self.head(feat)


def train_model(model, train_loader, epochs, lr, device, label="",
                checkpoint_dir=None, upload_fn=None, s3_path=None):
    """Train and return loss history. Saves checkpoint after each epoch."""
    model.to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()
    losses = []

    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        count = 0
        for images, targets in train_loader:
            images, targets = images.to(device), targets.to(device)
            optimizer.zero_grad()
            preds = model(images)
            loss = criterion(preds, targets)
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item() * len(images)
            count += len(images)

        avg_loss = epoch_loss / max(count, 1)
        losses.append(avg_loss)
        if (epoch + 1) % 5 == 0 or epoch == 0:
            print(f"  [{label}] Epoch {epoch+1}/{epochs}: loss={avg_loss:.6f}")

        # Save checkpoint for resumability
        if checkpoint_dir:
            ckpt_path = os.path.join(checkpoint_dir, f"checkpoint_{label}.pt")
            torch.save({
                "epoch": epoch,
                "model_state_dict": model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "loss": avg_loss,
            }, ckpt_path)

    return losses


def evaluate_model(model, eval_loader, device):
    """Evaluate on held-out set and return mean waypoint error."""
    model.eval()
    total_error = 0.0
    count = 0
    with torch.no_grad():
        for images, targets in eval_loader:
            images, targets = images.to(device), targets.to(device)
            preds = model(images)
            error = torch.sqrt(((preds - targets) ** 2).sum(dim=1)).mean()
            total_error += error.item() * len(images)
            count += len(images)
    return total_error / max(count, 1)


def main():
    args = parse_args()
    print("[Stage6] Starting baseline waypoint regressor training")

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from amr_utils.s3_sync import download_directory, upload_directory, make_stage_path

    # Download data
    raw_s3 = make_stage_path(args.s3_bucket, args.run_id, "raw-v1")
    aug_s3 = make_stage_path(args.s3_bucket, args.run_id, "augmented-v2")
    traj_s3 = make_stage_path(args.s3_bucket, args.run_id, "trajectories")

    print(f"[Stage6] Downloading raw data from {raw_s3}")
    download_directory(raw_s3, args.raw_dir)

    print(f"[Stage6] Downloading augmented data from {aug_s3}")
    download_directory(aug_s3, args.aug_dir)

    print(f"[Stage6] Downloading trajectories from {traj_s3}")
    download_directory(traj_s3, args.traj_dir)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[Stage6] Using device: {device}")

    # Load trajectory-derived waypoint labels
    waypoint_labels = load_trajectory_labels(args.traj_dir)
    print(f"[Stage6] Loaded {len(waypoint_labels)} waypoint labels from trajectories")

    os.makedirs(args.output_dir, exist_ok=True)

    # --- Experiment A: Train on raw-v1 only ---
    print("\n[Stage6] === Experiment A: Raw data only ===")
    ds_raw = NavigationDataset([args.raw_dir], waypoint_labels=waypoint_labels)
    print(f"  Dataset size: {len(ds_raw)}")

    if len(ds_raw) == 0:
        print("[Stage6] ERROR: No training samples found")
        sys.exit(1)

    # Train/eval split
    n_eval = max(1, int(len(ds_raw) * args.eval_split))
    n_train = len(ds_raw) - n_eval
    indices = list(range(len(ds_raw)))
    np.random.seed(42)
    np.random.shuffle(indices)
    train_idx, eval_idx = indices[:n_train], indices[n_train:]

    train_a = Subset(ds_raw, train_idx)
    eval_a = Subset(ds_raw, eval_idx)

    dl_train_a = DataLoader(train_a, batch_size=args.batch_size, shuffle=True, num_workers=2)
    dl_eval_a = DataLoader(eval_a, batch_size=args.batch_size, shuffle=False, num_workers=2)

    print(f"  Train: {len(train_a)}, Eval: {len(eval_a)}")

    model_a = WaypointNavigator()
    losses_a = train_model(model_a, dl_train_a, args.epochs, args.lr, device,
                           "Exp-A", checkpoint_dir=args.output_dir)
    error_a = evaluate_model(model_a, dl_eval_a, device)
    print(f"  [Exp-A] Final loss: {losses_a[-1]:.6f}, eval waypoint error: {error_a:.6f}")

    # --- Experiment B: Train on raw-v1 + augmented-v2 ---
    print("\n[Stage6] === Experiment B: Raw + Augmented ===")
    ds_combined = NavigationDataset([args.raw_dir, args.aug_dir], waypoint_labels=waypoint_labels)
    print(f"  Dataset size: {len(ds_combined)}")

    # Use same eval set (raw-only eval indices), train on everything else
    n_raw = len(ds_raw)
    train_b_idx = [i for i in range(len(ds_combined)) if i not in eval_idx]
    train_b = Subset(ds_combined, train_b_idx)
    eval_b = Subset(ds_combined, eval_idx)  # Same eval set for fair comparison

    dl_train_b = DataLoader(train_b, batch_size=args.batch_size, shuffle=True, num_workers=2)
    dl_eval_b = DataLoader(eval_b, batch_size=args.batch_size, shuffle=False, num_workers=2)

    print(f"  Train: {len(train_b)}, Eval: {len(eval_b)}")

    model_b = WaypointNavigator()
    losses_b = train_model(model_b, dl_train_b, args.epochs, args.lr, device,
                           "Exp-B", checkpoint_dir=args.output_dir)
    error_b = evaluate_model(model_b, dl_eval_b, device)
    print(f"  [Exp-B] Final loss: {losses_b[-1]:.6f}, eval waypoint error: {error_b:.6f}")

    # Save final model checkpoints
    torch.save(model_a.state_dict(), os.path.join(args.output_dir, "model_raw_only.pt"))
    torch.save(model_b.state_dict(), os.path.join(args.output_dir, "model_raw_augmented.pt"))

    metrics = {
        "experiment_a": {
            "name": "raw_only",
            "train_size": len(train_a),
            "eval_size": len(eval_a),
            "final_train_loss": losses_a[-1],
            "loss_history": losses_a,
            "eval_waypoint_error": error_a,
        },
        "experiment_b": {
            "name": "raw_plus_augmented",
            "train_size": len(train_b),
            "eval_size": len(eval_b),
            "final_train_loss": losses_b[-1],
            "loss_history": losses_b,
            "eval_waypoint_error": error_b,
        },
        "comparison": {
            "loss_improvement_pct": (losses_a[-1] - losses_b[-1]) / losses_a[-1] * 100
            if losses_a[-1] > 0 else 0,
            "error_improvement_pct": (error_a - error_b) / error_a * 100
            if error_a > 0 else 0,
        },
        "model": "ResNet18 baseline waypoint regressor (NOT X-Mobility)",
        "labels": "trajectory-derived waypoint offsets (dx, dy)",
        "eval_split": args.eval_split,
    }

    with open(os.path.join(args.output_dir, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)

    print(f"\n[Stage6] === Results (held-out eval set) ===")
    print(f"  Exp-A (raw only):        loss={losses_a[-1]:.6f}, error={error_a:.6f}")
    print(f"  Exp-B (raw+augmented):   loss={losses_b[-1]:.6f}, error={error_b:.6f}")
    print(f"  Loss improvement:        {metrics['comparison']['loss_improvement_pct']:.1f}%")
    print(f"  Error improvement:       {metrics['comparison']['error_improvement_pct']:.1f}%")

    # Upload results
    s3_path = make_stage_path(args.s3_bucket, args.run_id, "results")
    print(f"\n[Stage6] Uploading to {s3_path}")
    upload_directory(args.output_dir, s3_path)

    print("[Stage6] Done.")


if __name__ == "__main__":
    main()
