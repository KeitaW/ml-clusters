# EKS Cluster for Isaac Sim Synthetic Data Generation

Standalone Terraform configuration that provisions an EKS cluster with GPU nodes for running NVIDIA Isaac Sim workloads.

## What It Provisions

- **VPC** with 3 AZs, public/private subnets, NAT gateway
- **EKS** cluster (v1.31) with a system managed node group
- **Karpenter** for GPU node auto-provisioning (G5/G6 instances)
- **GPU Operator** (driver pre-installed on AMI, toolkit disabled)
- **S3 bucket** for SDG output data

## Prerequisites

- Terraform >= 1.10
- AWS CLI configured with permissions to create VPC, EKS, IAM resources
- `kubectl` for post-deploy verification

## Usage

```bash
# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed

# Deploy
terraform init
terraform plan
terraform apply

# Configure kubectl
$(terraform output -raw configure_kubectl)

# Verify GPU Operator
kubectl get pods -n gpu-operator

# Run Isaac Sim test case
# See ../../../3.test_cases/isaac-sim/MobilityGen/kubernetes/README.md
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
| `max_gpu_nodes` | Max GPU nodes Karpenter can provision | `4` |

## Architecture

```
VPC (10.0.0.0/16)
├── Public Subnets (NAT Gateway)
└── Private Subnets
    ├── EKS Control Plane
    ├── System Node Group (m5.xlarge x2)
    └── Karpenter GPU Nodes (G5/G6, on-demand)
        ├── GPU Operator (device plugin, DCGM)
        └── Isaac Sim Jobs
```
