# Isaac Sim MobilityGen - Synthetic Data Generation on EKS

This test case runs NVIDIA Isaac Sim's MobilityGen pipeline on Amazon EKS with GPU nodes to generate synthetic RGB, depth, and segmentation data from randomized robot trajectories in a warehouse environment.

## Overview

MobilityGen is an Isaac Sim extension for generating synthetic datasets for mobile robot navigation. This test case automates the pipeline (no interactive keyboard teleoperation) using `RandomPathFollowingScenario` to produce camera sensor data along computed trajectories.

**Output**: Per-frame RGB images, depth maps, and semantic segmentation masks.

## Prerequisites

- Amazon EKS cluster with GPU nodes (G5 or G6 instances)
- NVIDIA GPU Operator installed on the cluster
- Karpenter (recommended) or Cluster Autoscaler for GPU node provisioning
- [NVIDIA NGC](https://ngc.nvidia.com/) account and API key
- Docker, `kubectl`, and AWS CLI configured

## Quick Start

See [kubernetes/README.md](kubernetes/README.md) for step-by-step deployment instructions.

```bash
# 1. Create NGC pull secret
./kubernetes/0.setup-ngc-secret.sh

# 2. Build and push container image
./kubernetes/1.build-container.sh

# 3. Submit the SDG job
./kubernetes/2.submit-job.sh
```

## Configuration

Edit `configs/default_config.yaml` to customize:
- Scene USD path
- Number of trajectories and frames per trajectory
- Output image resolution
- Sensor types (RGB, depth, segmentation)

## Architecture

```
┌─────────────────────────────────────────┐
│  EKS Cluster                            │
│  ┌───────────────────────────────────┐  │
│  │  G5/G6 GPU Node (Karpenter)      │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Isaac Sim Container        │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │ automated_mobilitygen │  │  │  │
│  │  │  │ .py                   │  │  │  │
│  │  │  └───────┬───────────────┘  │  │  │
│  │  │          │                  │  │  │
│  │  │  ┌───────▼───────────────┐  │  │  │
│  │  │  │ /output/              │  │  │  │
│  │  │  │  rgb/ depth/ seg/     │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Instance Recommendations

| Instance | GPUs | GPU Memory | vCPUs | RAM    | Notes |
|----------|------|-----------|-------|--------|-------|
| g5.2xlarge | 1  | 24 GB     | 8     | 32 GB  | Minimum for basic SDG |
| g5.4xlarge | 1  | 24 GB     | 16    | 64 GB  | Recommended |
| g6.2xlarge | 1  | 24 GB     | 8     | 32 GB  | Latest generation |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Vulkan ICD not found | Ensure GPU Operator toolkit is enabled, or use `--/app/renderer/enabled=false` |
| OOM kills | Use g5.4xlarge+ (64 GB RAM); Isaac Sim needs ~30 GB during shader compilation |
| Shader compilation timeout | Increase `activeDeadlineSeconds` to 3600 (60 min) on first run |
| Slow image pull | Use instance types with NVMe instance store; configure `instanceStorePolicy: RAID0` |
