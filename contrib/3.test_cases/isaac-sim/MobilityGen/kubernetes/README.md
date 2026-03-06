# MobilityGen on Kubernetes (Amazon EKS)

Step-by-step instructions for running Isaac Sim MobilityGen synthetic data generation on Amazon EKS with GPU nodes.

## Prerequisites

1. **Amazon EKS cluster** with Kubernetes 1.29+ and Karpenter installed
2. **GPU nodes**: G5 or G6 instances with NVIDIA GPU Operator
3. **NGC API key**: Sign up at [ngc.nvidia.com](https://ngc.nvidia.com/) and generate an API key
4. **Tools**: `kubectl`, `docker`, `aws` CLI, `envsubst`

## Step 1: Create NGC Image Pull Secret

```bash
export NGC_API_KEY="<your-ngc-api-key>"
./0.setup-ngc-secret.sh
```

This creates the `isaac-sim` namespace and an `ngc-secret` for pulling `nvcr.io/nvidia/isaac-sim:5.1.0`.

## Step 2: Build Container Image

```bash
export NGC_API_KEY="<your-ngc-api-key>"
./1.build-container.sh
```

This builds the MobilityGen image on top of Isaac Sim and pushes it to Amazon ECR. The script outputs the `IMAGE_URI` to export.

## Step 3: Set Environment Variables

```bash
export IMAGE_URI="<account-id>.dkr.ecr.<region>.amazonaws.com/isaac-sim-mobilitygen:latest"
export NAMESPACE="isaac-sim"
export NUM_TRAJECTORIES="5"
```

## Step 4: Submit SDG Job

```bash
./2.submit-job.sh
```

## Step 5: Monitor

```bash
# Watch pod scheduling and node provisioning
kubectl get pods -n isaac-sim -w

# Stream logs (expect ~5-10 min shader compilation on first run)
kubectl logs -f job/mobilitygen-sdg -n isaac-sim

# Check Karpenter provisioned a G-series node
kubectl get nodes -l karpenter.k8s.aws/instance-category=g
```

## Step 6: Verify Output

When the job completes, logs will show per-frame file listing with sizes:

```
[MobilityGen] Pipeline complete. Total frames: 500, output: /output
  /output/rgb/frame_0001.png (0.9 MB)
  /output/distance_to_image_plane/frame_0001.npy (1.2 MB)
  /output/semantic_segmentation/frame_0001.png (0.1 MB)
  ...
```

To copy output locally:

```bash
POD=$(kubectl get pods -n isaac-sim -l job-name=mobilitygen-sdg -o jsonpath='{.items[0].metadata.name}')
kubectl cp isaac-sim/${POD}:/output ./mobilitygen-output
```

## (Optional) OSMO Workflow

If your cluster has [NVIDIA OSMO](https://developer.nvidia.com/osmo) installed:

```bash
envsubst < mobilitygen-osmo-workflow.yaml | osmo workflow submit -f -
osmo workflow status <workflow-id>
osmo workflow logs <workflow-id>
```

## Cleanup

```bash
kubectl delete job mobilitygen-sdg -n isaac-sim
kubectl delete namespace isaac-sim
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck in `Pending` | No GPU nodes available | Check Karpenter NodePool allows G-series instances |
| `ImagePullBackOff` | NGC auth failed | Verify `NGC_API_KEY` and re-run `0.setup-ngc-secret.sh` |
| `OOMKilled` | Insufficient memory | Use g5.4xlarge+ (64GB RAM) |
| Vulkan errors in logs | Missing GPU driver/toolkit | Enable `toolkit.enabled=true` in GPU Operator values |
| Job timeout | Shader compilation slow | Increase `activeDeadlineSeconds` in job template |
