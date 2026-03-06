#!/usr/bin/env python3
"""Stage 6: Training + Evaluation.

Downloads raw-v1/ and augmented-v2/ from S3, trains a simple CNN navigator
(ResNet18 + waypoint prediction head), compares raw-only vs raw+augmented.

Usage:
    python /scripts/stage6_train_evaluate.py \
        --s3_bucket my-bucket --run_id run-001
"""

import argparse
import functools
import json
import os
import sys

print = functools.partial(print, flush=True)

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms


def parse_args():
    parser = argparse.ArgumentParser(description="Stage 6: Train + Evaluate")
    parser.add_argument("--s3_bucket", type=str, required=True)
    parser.add_argument("--run_id", type=str, required=True)
    parser.add_argument("--raw_dir", type=str, default="/input/raw-v1")
    parser.add_argument("--aug_dir", type=str, default="/input/augmented-v2")
    parser.add_argument("--output_dir", type=str, default="/output/results")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch_size", type=int, default=16)
    parser.add_argument("--lr", type=float, default=1e-4)
    return parser.parse_args()


class NavigationDataset(Dataset):
    """Dataset of RGB frames with synthetic waypoint labels."""

    def __init__(self, rgb_dirs, transform=None):
        self.samples = []
        self.transform = transform or transforms.Compose([
            transforms.ToPILImage(),
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406],
                                 std=[0.229, 0.224, 0.225]),
        ])

        for rgb_dir in rgb_dirs:
            if not os.path.exists(rgb_dir):
                continue
            files = sorted([
                f for f in os.listdir(rgb_dir)
                if f.lower().endswith((".png", ".jpg", ".jpeg"))
            ])
            for i, fname in enumerate(files):
                # Synthetic waypoint: next position offset (dx, dy)
                # In a real pipeline these come from trajectory data
                t = i / max(len(files) - 1, 1)
                dx = np.cos(t * np.pi) * 0.5  # Simulated forward offset
                dy = np.sin(t * np.pi) * 0.2  # Simulated lateral offset
                self.samples.append((os.path.join(rgb_dir, fname), [dx, dy]))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        img_path, waypoint = self.samples[idx]
        from PIL import Image
        img = np.array(Image.open(img_path).convert("RGB"))
        img = self.transform(img)
        return img, torch.tensor(waypoint, dtype=torch.float32)


class WaypointNavigator(nn.Module):
    """ResNet18 backbone + FC head for waypoint offset prediction."""

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


def train_model(model, dataloader, epochs, lr, device, label=""):
    """Train and return loss history."""
    model.to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()
    losses = []

    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        count = 0
        for images, targets in dataloader:
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

    return losses


def evaluate_model(model, dataloader, device):
    """Evaluate and return mean waypoint error."""
    model.eval()
    total_error = 0.0
    count = 0
    with torch.no_grad():
        for images, targets in dataloader:
            images, targets = images.to(device), targets.to(device)
            preds = model(images)
            error = torch.sqrt(((preds - targets) ** 2).sum(dim=1)).mean()
            total_error += error.item() * len(images)
            count += len(images)
    return total_error / max(count, 1)


def main():
    args = parse_args()
    print("[Stage6] Starting training and evaluation")

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from utils.s3_sync import download_directory, upload_directory, make_stage_path

    # Download data
    raw_s3 = make_stage_path(args.s3_bucket, args.run_id, "raw-v1")
    aug_s3 = make_stage_path(args.s3_bucket, args.run_id, "augmented-v2")

    print(f"[Stage6] Downloading raw data from {raw_s3}")
    download_directory(raw_s3, args.raw_dir)

    print(f"[Stage6] Downloading augmented data from {aug_s3}")
    download_directory(aug_s3, args.aug_dir)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[Stage6] Using device: {device}")

    raw_rgb = os.path.join(args.raw_dir, "rgb")
    aug_rgb = os.path.join(args.aug_dir, "rgb")

    # Experiment A: Train on raw-v1 only
    print("\n[Stage6] === Experiment A: Raw data only ===")
    ds_raw = NavigationDataset([raw_rgb])
    print(f"  Dataset size: {len(ds_raw)}")

    if len(ds_raw) == 0:
        print("[Stage6] ERROR: No training samples found")
        sys.exit(1)

    dl_raw = DataLoader(ds_raw, batch_size=args.batch_size, shuffle=True, num_workers=2)

    model_a = WaypointNavigator()
    losses_a = train_model(model_a, dl_raw, args.epochs, args.lr, device, "Exp-A")
    error_a = evaluate_model(model_a, dl_raw, device)
    print(f"  [Exp-A] Final loss: {losses_a[-1]:.6f}, mean waypoint error: {error_a:.6f}")

    # Experiment B: Train on raw-v1 + augmented-v2
    print("\n[Stage6] === Experiment B: Raw + Augmented ===")
    ds_combined = NavigationDataset([raw_rgb, aug_rgb])
    print(f"  Dataset size: {len(ds_combined)}")

    dl_combined = DataLoader(ds_combined, batch_size=args.batch_size, shuffle=True, num_workers=2)

    model_b = WaypointNavigator()
    losses_b = train_model(model_b, dl_combined, args.epochs, args.lr, device, "Exp-B")
    error_b = evaluate_model(model_b, dl_combined, device)
    print(f"  [Exp-B] Final loss: {losses_b[-1]:.6f}, mean waypoint error: {error_b:.6f}")

    # Save results
    os.makedirs(args.output_dir, exist_ok=True)

    torch.save(model_a.state_dict(), os.path.join(args.output_dir, "checkpoint_raw_only.pt"))
    torch.save(model_b.state_dict(), os.path.join(args.output_dir, "checkpoint_raw_augmented.pt"))

    metrics = {
        "experiment_a": {
            "name": "raw_only",
            "dataset_size": len(ds_raw),
            "final_loss": losses_a[-1],
            "loss_history": losses_a,
            "mean_waypoint_error": error_a,
        },
        "experiment_b": {
            "name": "raw_plus_augmented",
            "dataset_size": len(ds_combined),
            "final_loss": losses_b[-1],
            "loss_history": losses_b,
            "mean_waypoint_error": error_b,
        },
        "comparison": {
            "loss_improvement": (losses_a[-1] - losses_b[-1]) / losses_a[-1] * 100
            if losses_a[-1] > 0 else 0,
            "error_improvement": (error_a - error_b) / error_a * 100
            if error_a > 0 else 0,
        },
    }

    with open(os.path.join(args.output_dir, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)

    print(f"\n[Stage6] === Results ===")
    print(f"  Exp-A (raw only):        loss={losses_a[-1]:.6f}, error={error_a:.6f}")
    print(f"  Exp-B (raw+augmented):   loss={losses_b[-1]:.6f}, error={error_b:.6f}")
    print(f"  Loss improvement:        {metrics['comparison']['loss_improvement']:.1f}%")
    print(f"  Error improvement:       {metrics['comparison']['error_improvement']:.1f}%")

    # Upload results
    s3_path = make_stage_path(args.s3_bucket, args.run_id, "results")
    print(f"\n[Stage6] Uploading to {s3_path}")
    upload_directory(args.output_dir, s3_path)

    print("[Stage6] Done.")


if __name__ == "__main__":
    main()
