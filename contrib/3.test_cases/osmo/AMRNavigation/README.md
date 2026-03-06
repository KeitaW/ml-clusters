# Warehouse AMR Navigation Pipeline on NVIDIA OSMO

MobilityGen-style synthetic data generation pipeline for warehouse AMR (Autonomous Mobile Robot) navigation, running on Amazon EKS with NVIDIA OSMO orchestration and KAI Scheduler.

## Overview

This test case includes two modes:

1. **Single-stage SDG** (legacy): One-shot MobilityGen data generation using `automated_mobilitygen.py`
2. **6-stage AMR pipeline**: Full scene-to-training demo workflow orchestrated as an OSMO DAG

This is a **demo pipeline** for validating the OSMO + EKS + Karpenter integration. Stage 6 trains a baseline waypoint regressor (ResNet18), not a production navigation model.

### 6-Stage Pipeline Architecture

```
scene-setup --> occupancy-map --> trajectory-gen --> render --+--> domain-augment --> train-evaluate
                                                             |                            ^
                                                             +----------------------------+
```

| Stage | Script | Image | GPU Pool | Purpose |
|-------|--------|-------|----------|---------|
| 1. Scene Setup | `stage1_scene_setup.py` | isaac-sim-amr | G-series (rendering) | Build warehouse USD scene |
| 2. Occupancy Map | `stage2_occupancy_map.py` | isaac-sim-amr | G-series (rendering) | 2D occupancy grid from prim geometry |
| 3. Trajectory Gen | `stage3_trajectory_gen.py` | isaac-sim-amr | G-series (rendering) | A* path planning + camera poses |
| 4. Render | `stage4_render.py` | isaac-sim-amr | G-series (rendering) | RGB/depth/segmentation rendering |
| 5. Domain Augment | `stage5_domain_augment.py` | cosmos-transfer-amr | G-series (rendering) | Visual augmentation (torchvision, Cosmos Transfer-compatible) |
| 6. Train+Eval | `stage6_train_evaluate.py` | xmobility-amr | P-series (training) | Baseline waypoint regressor, A vs B comparison |

**OSMO orchestration features used:**
- DAG task dependencies via `inputs:`
- KAI Scheduler assignment via `schedulerName: kai-scheduler`
- Priority scheduling via `priority: medium`
- Checkpoint/reschedule semantics via `exitAction: reschedule` on training stage
- Heterogeneous compute: G-series (rendering) and P-series (training) NodePools

**Data passing**: S3 bucket via IRSA. Path: `s3://<bucket>/amr-pipeline/<run-id>/<stage>/`

## Prerequisites

- Amazon EKS cluster with GPU nodes (G5/G6 for rendering, P-series for training)
- NVIDIA GPU Operator + KAI Scheduler + OSMO Platform installed
- Karpenter with separate NodePools for rendering (G-series) and training (P-series)
- [NVIDIA NGC](https://ngc.nvidia.com/) account and API key
- S3 bucket for inter-stage data + IRSA ServiceAccount
- Docker, `kubectl`, and AWS CLI configured

## Quick Start

### Single-Stage (Legacy)

```bash
./kubernetes/0.setup-ngc-secret.sh
./kubernetes/1.build-container.sh
./kubernetes/2.submit-job.sh
```

### Full 6-Stage Pipeline

```bash
# 1. Setup
./kubernetes/0.setup-ngc-secret.sh

# 2. Build all 3 images
./kubernetes/1.build-container.sh

# 3. Submit pipeline
export S3_BUCKET="my-amr-pipeline-bucket"
./kubernetes/3.submit-pipeline.sh
```

See [kubernetes/README.md](kubernetes/README.md) for detailed per-stage instructions.

## Configuration

- `configs/default_config.yaml` - Single-stage and pipeline-level settings
- `configs/pipeline_config.yaml` - Per-stage pipeline parameters

## Container Images

| Image | Dockerfile | Base | Stages |
|-------|-----------|------|--------|
| `isaac-sim-mobilitygen` | `Dockerfile` | Isaac Sim 5.1.0 | Legacy single-stage |
| `isaac-sim-amr` | `Dockerfile.isaac-sim` | Isaac Sim 5.1.0 | 1-4 (scene, occupancy, trajectory, render) |
| `cosmos-transfer-amr` | `Dockerfile.cosmos-transfer` | PyTorch 24.05 | 5 (domain augmentation) |
| `xmobility-amr` | `Dockerfile.xmobility` | PyTorch 24.05 | 6 (baseline training + evaluation) |

## S3 Output Structure

```
s3://<bucket>/amr-pipeline/<run-id>/
  scene/              # warehouse_scene.usd + metadata.json
  occupancy/          # occupancy_map.npy + .png + metadata.json
  trajectories/       # trajectory_XXXX.json files + metadata.json
  raw-v1/             # rgb/ depth/ semantic_segmentation/
  augmented-v2/       # rgb/ depth/ semantic_segmentation/
  results/            # model_*.pt + metrics.json
```

## Instance Recommendations

| Instance | GPUs | GPU Memory | vCPUs | RAM | Use |
|----------|------|-----------|-------|-----|-----|
| g5.4xlarge | 1 | 24 GB | 16 | 64 GB | Stages 1-5 (rendering, augmentation) |
| g6.2xlarge | 1 | 24 GB | 8 | 32 GB | Stages 1-5 (latest gen) |
| p4d.24xlarge | 8 | 320 GB | 96 | 1152 GB | Stage 6 (training) |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Vulkan ICD not found | Ensure GPU Operator toolkit is enabled (`toolkit.enabled=true`) |
| OOM kills | Use g5.4xlarge+ (64 GB RAM) for Isaac Sim stages |
| Shader compilation timeout | Increase `activeDeadlineSeconds` to 3600 on first run |
| S3 access denied | Verify IRSA ServiceAccount annotation matches IAM role ARN |
| Stage stuck on download | Check S3 bucket region matches cluster region |
| Training NaN loss | Reduce learning rate or check augmented data integrity |
