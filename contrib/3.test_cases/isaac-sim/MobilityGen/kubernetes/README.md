# MobilityGen on Kubernetes (Amazon EKS)

Step-by-step instructions for running Isaac Sim MobilityGen on Amazon EKS. Supports both single-stage SDG and the full 6-stage AMR navigation pipeline.

## Prerequisites

1. **Amazon EKS cluster** with Kubernetes 1.29+ and Karpenter installed
2. **GPU nodes**: G5/G6 instances (rendering) + P-series (training) with NVIDIA GPU Operator
3. **NVIDIA OSMO** installed (for pipeline mode)
4. **NGC API key**: Sign up at [ngc.nvidia.com](https://ngc.nvidia.com/) and generate an API key
5. **S3 bucket** for inter-stage data (pipeline mode) with IRSA configured
6. **Tools**: `kubectl`, `docker`, `aws` CLI, `envsubst`

## Single-Stage SDG (Legacy)

### Step 1: Create NGC Image Pull Secret

```bash
export NGC_API_KEY="<your-ngc-api-key>"
./0.setup-ngc-secret.sh
```

### Step 2: Build Container Image

```bash
export NGC_API_KEY="<your-ngc-api-key>"
./1.build-container.sh
```

### Step 3: Submit Job

```bash
export IMAGE_URI="<account-id>.dkr.ecr.<region>.amazonaws.com/isaac-sim-mobilitygen:latest"
./2.submit-job.sh
```

### Step 4: Monitor

```bash
kubectl get pods -n isaac-sim -w
kubectl logs -f job/mobilitygen-sdg -n isaac-sim
```

---

## 6-Stage AMR Navigation Pipeline

### Step 1: Setup

```bash
export NGC_API_KEY="<your-ngc-api-key>"
./0.setup-ngc-secret.sh
```

### Step 2: Build All Images

```bash
./1.build-container.sh
```

This builds 4 images (1 legacy + 3 pipeline):
- `isaac-sim-mobilitygen:latest` (legacy)
- `isaac-sim-amr:latest` (stages 1-4)
- `cosmos-transfer-amr:latest` (stage 5)
- `xmobility-amr:latest` (stage 6)

### Step 3: Submit Full Pipeline

```bash
export ISAAC_SIM_IMAGE_URI="<account>.dkr.ecr.<region>.amazonaws.com/isaac-sim-amr:latest"
export COSMOS_IMAGE_URI="<account>.dkr.ecr.<region>.amazonaws.com/cosmos-transfer-amr:latest"
export XMOBILITY_IMAGE_URI="<account>.dkr.ecr.<region>.amazonaws.com/xmobility-amr:latest"
export S3_BUCKET="my-amr-pipeline-bucket"
export RUN_ID="run-001"

./3.submit-pipeline.sh
```

### Step 4: Monitor Pipeline

```bash
# Watch all pipeline pods
kubectl get pods -n isaac-sim -w

# Watch OSMO workflow status
kubectl get workflows -n isaac-sim -w

# Check specific stage logs
kubectl logs -f -l osmo.nvidia.com/task-name=scene-setup -n isaac-sim
kubectl logs -f -l osmo.nvidia.com/task-name=render -n isaac-sim
kubectl logs -f -l osmo.nvidia.com/task-name=train-evaluate -n isaac-sim
```

### Running Individual Stages

Each stage can be tested independently as a K8s Job:

```bash
export NAMESPACE="isaac-sim"
export S3_BUCKET="my-bucket"
export RUN_ID="test-001"
export ISAAC_SIM_IMAGE_URI="<uri>"

# Run just stage 1
envsubst < stage1-job.yaml | kubectl apply -f -
kubectl logs -f job/amr-stage1-scene-setup -n isaac-sim

# After stage 1 completes, run stage 2
envsubst < stage2-job.yaml | kubectl apply -f -

# Continue sequentially, or jump to any stage if its S3 inputs exist
```

### Step 5: Verify Output

Check S3 for pipeline artifacts:

```bash
# List all stage outputs
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/ --recursive --summarize

# Stage-specific checks
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/scene/
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/occupancy/
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/trajectories/
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/raw-v1/
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/augmented-v2/
aws s3 ls s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/results/

# Download training metrics
aws s3 cp s3://${S3_BUCKET}/amr-pipeline/${RUN_ID}/results/metrics.json .
cat metrics.json
```

## File Reference

| File | Purpose |
|------|---------|
| `0.setup-ngc-secret.sh` | Create NGC image pull secret |
| `1.build-container.sh` | Build and push all container images |
| `2.submit-job.sh` | Submit legacy single-stage job |
| `3.submit-pipeline.sh` | Submit full 6-stage OSMO pipeline |
| `serviceaccount.yaml` | IRSA ServiceAccount for S3 access |
| `stage{1-6}-job.yaml` | Per-stage standalone K8s Job templates |
| `amr-pipeline-workflow.yaml` | OSMO 6-task DAG template |
| `mobilitygen-job.yaml-template` | Legacy single-stage job template |
| `mobilitygen-osmo-workflow.yaml` | Legacy single-stage OSMO workflow |

## Cleanup

```bash
# Delete pipeline
kubectl delete workflow amr-navigation-pipeline -n isaac-sim

# Delete individual stage jobs
kubectl delete jobs -l app=amr-pipeline -n isaac-sim

# Delete legacy job
kubectl delete job mobilitygen-sdg -n isaac-sim

# Full cleanup
kubectl delete namespace isaac-sim
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod stuck in `Pending` | No GPU nodes available | Check Karpenter NodePool for G/P-series |
| `ImagePullBackOff` | NGC auth failed | Verify `NGC_API_KEY` and re-run `0.setup-ngc-secret.sh` |
| `OOMKilled` | Insufficient memory | Use g5.4xlarge+ (64GB RAM) for Isaac Sim stages |
| Vulkan errors in logs | Missing GPU driver/toolkit | Enable `toolkit.enabled=true` in GPU Operator values |
| Job timeout | Shader compilation slow | Increase `activeDeadlineSeconds` in job template |
| S3 `AccessDenied` | IRSA misconfigured | Check ServiceAccount annotation and IAM role trust policy |
| Stage fails on download | Previous stage didn't complete | Check preceding stage logs and S3 output |
| Training NaN loss | Bad augmented data | Inspect augmented-v2/ images, reduce learning rate |
