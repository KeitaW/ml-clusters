# EKS Demo Cluster for OSMO AMR Navigation Pipeline

Demo Terraform configuration that provisions an EKS cluster with heterogeneous GPU capacity for running the warehouse AMR synthetic data generation pipeline with NVIDIA OSMO orchestration.

This is a **demo/test architecture** — for production deployments, pin AMI versions, restrict the cluster endpoint to private, and add more granular disruption budgets.

## What It Provisions

- **VPC** with 3 AZs, public/private subnets, NAT gateway
- **EKS** cluster (v1.31) with a system managed node group
- **Karpenter** with two GPU NodePools:
  - `isaac-sim-rendering` — G5/G6 instances for rendering stages (1-5)
  - `gpu-training` — P6-B300 instances for X-Mobility training (stage 6), backed by Capacity Block
- **GPU Operator** (driver pre-installed on AMI, toolkit enabled)
- **S3 bucket** for inter-stage pipeline data
- **IRSA role** for pipeline ServiceAccount S3 access

## Prerequisites

- Terraform >= 1.10
- AWS CLI configured with permissions to create VPC, EKS, IAM resources
- EC2 Capacity Block for training instances (p6-b300.48xlarge)
- `kubectl` for post-deploy verification

## Usage

```bash
# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set capacity_reservation_id to your ODCR

# Deploy
terraform init
terraform plan
terraform apply

# Configure kubectl
$(terraform output -raw configure_kubectl)

# Verify GPU Operator
kubectl get pods -n gpu-operator

# Create pipeline ServiceAccount (use IRSA role ARN from output)
IRSA_ARN=$(terraform output -raw pipeline_irsa_role_arn)
kubectl create namespace isaac-sim
kubectl create serviceaccount amr-pipeline-sa -n isaac-sim
kubectl annotate serviceaccount amr-pipeline-sa -n isaac-sim \
  eks.amazonaws.com/role-arn=$IRSA_ARN

# Run AMR pipeline test case
# See ../../../3.test_cases/osmo/AMRNavigation/kubernetes/README.md
```

## Cleanup

```bash
# Delete any K8s workloads first (Karpenter nodes)
kubectl delete jobs --all -n isaac-sim

# Destroy infrastructure
terraform destroy
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `cluster_name` | EKS cluster name | `isaac-sim-eks` |
| `cluster_version` | Kubernetes version | `1.31` |
| `region` | AWS region | `us-west-2` |
| `gpu_instance_types` | GPU instance types for rendering | `["g5.2xlarge", "g5.4xlarge", "g6.2xlarge"]` |
| `max_gpu_nodes` | Max rendering GPU nodes (G-series) | `4` |
| `training_instance_type` | Training instance type | `p6-b300.48xlarge` |
| `max_training_gpus` | Max training GPUs | `48` |

## Architecture

```
VPC (10.0.0.0/16)
+-- Public Subnets (NAT Gateway)
+-- Private Subnets
    +-- EKS Control Plane
    +-- System Node Group (m5.xlarge x2)
    +-- Karpenter Rendering Pool (G5/G6, on-demand)
    |   +-- GPU Operator (device plugin, DCGM)
    |   +-- Isaac Sim Jobs (stages 1-5)
    +-- Karpenter Training Pool (p6-b300.48xlarge, Capacity Block)
        +-- X-Mobility Training (stage 6, 8 GPUs per node)
```
