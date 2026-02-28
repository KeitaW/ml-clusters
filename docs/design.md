# Design Doc: AWS ML Cluster Management with GitOps + Terraform

**Author**: ML Infrastructure Team
**Date**: 2026-02-28
**Status**: Draft
**Reviewers**: TBD

---

## 1. Context and Problem Statement

We operate ML training and inference workloads across multiple AWS cluster types — AWS ParallelCluster (Slurm), Amazon EKS (Kubernetes), and Amazon SageMaker HyperPod (Slurm and Kubernetes orchestrators) — spanning two AWS accounts and multiple regions.

Today, cluster provisioning is manual and inconsistent. Each cluster type uses different tooling (CLI, console, CloudFormation), making it difficult to:

- Reproduce environments across accounts/regions
- Audit what infrastructure exists and who changed it
- Share foundational resources (VPC, storage, IAM) across cluster types
- Reserve GPU capacity (P5, P5e) in a coordinated way
- Onboard new team members without tribal knowledge

This design proposes a unified infrastructure management system using **Terraform + Terragrunt** for infrastructure provisioning, **Atlantis** for PR-based GitOps workflows, **ArgoCD** for Kubernetes workload management, and **Claude Code skills** for GPU capacity procurement.

### Scope

| In Scope | Out of Scope |
|----------|-------------|
| Infrastructure provisioning (VPC, storage, IAM, clusters) | ML training framework selection (PyTorch vs JAX) |
| GitOps workflow for infrastructure changes | Job scheduling policies and queue priorities |
| S3 data distribution across regions/accounts | Data pipeline orchestration (Airflow, Step Functions) |
| GPU capacity reservation (Capacity Blocks, Training Plans) | Model serving architecture |
| Observability stack deployment | Application-level monitoring dashboards |
| Claude Code skills for capacity management | Cost optimization automation |

---

## 2. Goals and Non-Goals

### Goals

1. **Single source of truth**: All infrastructure defined in a Git monorepo with Terraform/Terragrunt. No manual console changes.
2. **Multi-account, multi-region**: Support accounts 483026362307 (management + workload) and 159553542841 (workload) across multiple regions.
3. **Cluster-type agnostic shared infra**: VPC, FSx Lustre, EFS, IAM, and KMS shared across ParallelCluster, EKS, and HyperPod.
4. **PR-based change management**: All infrastructure changes go through PR review with automated `terraform plan` via Atlantis.
5. **Data locality**: Central S3 bucket (us-east-1) replicated to per-region buckets so clusters read from local storage.
6. **GPU capacity procurement**: Claude Code skills to search, compare, and purchase EC2 Capacity Blocks and SageMaker Training Plans.
7. **Reproducibility**: Any cluster can be torn down and recreated from Git state.

### Non-Goals

- **Multi-cloud**: AWS only. No GCP/Azure abstraction layers.
- **Cluster autoscaling policy design**: We provision the infrastructure; scheduling policies are configured separately.
- **CI/CD for ML code**: This system manages infrastructure, not training scripts or model artifacts.
- **Cost optimization automation**: Cost visibility yes, automated rightsizing no.

---

## 3. Background and Prior Art

### Cluster Type Comparison

| | ParallelCluster | EKS | HyperPod (Slurm) | HyperPod (EKS) |
|---|---|---|---|---|
| **Orchestrator** | Slurm | Kubernetes | Slurm | Kubernetes |
| **GPU health checks** | DCGM-based (opt-in) | None built-in | Deep health checks (DCGM L4, NCCL, EFA) | Deep health checks + Health Monitoring Agent |
| **Auto node replacement** | No | No | Yes | Yes |
| **Auto-resume training** | No | No | Yes (`--auto-resume=1`) | Yes (KubeFlow PyTorchJob) |
| **Terraform provider** | `aws-tf/aws-parallelcluster` | `hashicorp/aws` | `hashicorp/awscc` | `hashicorp/awscc` + `hashicorp/aws` |
| **TF module maturity** | Official module v1.1.0 | Community module v21.15.1 | No module (raw resource) | No module |
| **Best for** | Traditional HPC, Slurm-native teams | K8s-native teams, inference | Large-scale training with fault tolerance | K8s teams wanting HyperPod resiliency |

### When to Use Which

```
Need fault-tolerant multi-node training?
  ├─ Yes → Need Kubernetes API?
  │         ├─ Yes → HyperPod (EKS orchestrator)
  │         └─ No  → HyperPod (Slurm orchestrator)
  └─ No  → Team prefers Slurm or Kubernetes?
            ├─ Slurm      → ParallelCluster
            └─ Kubernetes → EKS with Karpenter
```

### Terraform Provider Landscape

Each cluster type requires a different Terraform provider — the single largest complexity driver in this design:

| Cluster | Provider | Why Separate |
|---------|----------|-------------|
| ParallelCluster | `aws-tf/aws-parallelcluster` v1.1.0 | Communicates via ParallelCluster API (API Gateway + Lambda), not AWS APIs directly |
| EKS | `hashicorp/aws` v6.x (via `terraform-aws-modules/eks/aws` v21.15.1, requires >= 6.28) | Native AWS resource |
| HyperPod | `hashicorp/awscc` >= v1.25.0 | Uses Cloud Control API; no `hashicorp/aws` resource exists |
| Shared infra | `hashicorp/aws` v6.x | VPC, FSx, EFS, IAM, KMS, S3 |

---

## 4. Proposed Design

### 4.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Git Monorepo (ml-clusters)                     │
│                                                                         │
│  modules/          live/                gitops/         cluster-configs/ │
│  (TF modules)      (Terragrunt)        (ArgoCD apps)  (YAML, scripts)  │
└────────┬──────────────┬────────────────────┬───────────────┬────────────┘
         │              │                    │               │
    ┌────▼────┐   ┌─────▼─────┐      ┌──────▼──────┐  ┌────▼─────┐
    │Atlantis │   │ Terragrunt│      │   ArgoCD    │  │  S3      │
    │(PR plan/│   │ (generate │      │   (sync     │  │  (life-  │
    │ apply)  │   │  providers│      │    K8s      │  │   cycle  │
    └────┬────┘   │  + state) │      │    state)   │  │   scripts│
         │        └─────┬─────┘      └──────┬──────┘  └────┬─────┘
         │              │                    │               │
         ▼              ▼                    ▼               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    AWS Account 483026362307 (main)                       │
│                                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │   VPC    │  │FSx Lustre│  │   EKS    │  │Parallel- │  │ HyperPod │ │
│  │(shared)  │  │  + EFS   │  │ clusters │  │ Cluster  │  │ clusters │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘ │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                             │
│  │S3 central│  │ TF state │  │   ECR    │                             │
│  │data (hub)│  │  bucket  │  │ registry │                             │
│  └────┬─────┘  └──────────┘  └──────────┘                             │
│       │ CRR                                                             │
└───────┼─────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                  AWS Account 159553542841 (secondary)                    │
│                                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │   VPC    │  │FSx Lustre│  │   EKS    │  │ HyperPod │               │
│  │(per-rgn) │  │(per-rgn) │  │ clusters │  │ clusters │               │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘               │
│  ┌──────────┐                                                           │
│  │S3 replica│                                                           │
│  │ buckets  │                                                           │
│  └──────────┘                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Repository Structure

```
ml-clusters/
  modules/                                    # Reusable Terraform modules
    networking/                               # VPC, subnets, SGs, placement groups
      main.tf
      variables.tf
      outputs.tf
    shared-storage/                           # FSx Lustre, EFS
    s3-data-bucket/                           # S3 bucket with versioning + encryption
    s3-replication/                           # Cross-region/cross-account replication
    iam/                                      # IAM roles, policies, KMS keys
    eks-cluster/                              # Wraps terraform-aws-modules/eks/aws
    parallelcluster/                          # Wraps aws-tf/parallelcluster/aws
    hyperpod/                                 # Wraps awscc_sagemaker_cluster
    monitoring/                               # AMP, AMG, CloudWatch
    argocd/                                   # ArgoCD hub install + spoke registration
    atlantis/                                 # Atlantis server deployment
  live/
    terragrunt.hcl                            # Root: remote_state, generate provider
    _envcommon/                               # Shared component configs (DRY)
      networking.hcl
      eks-cluster.hcl
      parallelcluster.hcl
      hyperpod.hcl
    main-account/                             # 483026362307
      account.hcl
      us-east-1/
        region.hcl
        networking/terragrunt.hcl
        iam/terragrunt.hcl
        s3-central-data/terragrunt.hcl
        s3-tfstate/terragrunt.hcl
        s3-replication/terragrunt.hcl
        shared-storage/terragrunt.hcl
        eks-training/terragrunt.hcl
        argocd/terragrunt.hcl                    # Hub-only: ArgoCD install + spoke registration
        parallelcluster/terragrunt.hcl
        monitoring/terragrunt.hcl
      us-west-2/
        region.hcl
        networking/terragrunt.hcl
        s3-data-replica/terragrunt.hcl
        shared-storage/terragrunt.hcl
        eks-inference/terragrunt.hcl
    secondary-account/                        # 159553542841
      account.hcl
      us-west-2/
        region.hcl
        networking/terragrunt.hcl
        iam/terragrunt.hcl
        s3-data-replica/terragrunt.hcl
        shared-storage/terragrunt.hcl
        eks-training/terragrunt.hcl
        hyperpod-slurm/terragrunt.hcl
  cluster-configs/
    parallelcluster/                          # ParallelCluster YAML configs
      training-cluster.yaml
    hyperpod/
      lifecycle-scripts/                      # on_create.sh, lifecycle_script.py
        base-config/
  gitops/
    bootstrap/                                # ArgoCD bootstrap ApplicationSets
    add-ons/                                  # Helm values for cluster add-ons
    workloads/                                # Training job definitions
  skills/                                     # Claude Code skills
    capacity-blocks/
    training-plans/
  tests/
    unit/*.tftest.hcl
    integration/*.go
  atlantis.yaml                               # Atlantis project config
```

### 4.3 Layer 1: Shared Infrastructure

#### 4.3.1 VPC and Networking

Each account/region gets its own VPC with non-overlapping CIDRs. All cluster types within an account/region share the VPC.

**CIDR Allocation Scheme:**

| Account | Region | VPC CIDR | Private Subnets | Public Subnets |
|---------|--------|----------|-----------------|----------------|
| 483026362307 | us-east-1 | 10.0.0.0/16 | 10.0.0.0/18, 10.0.64.0/18 | 10.0.128.0/24, 10.0.129.0/24 |
| 483026362307 | us-west-2 | 10.1.0.0/16 | 10.1.0.0/18, 10.1.64.0/18 | 10.1.128.0/24, 10.1.129.0/24 |
| 159553542841 | us-east-1 | 10.2.0.0/16 (reserved) | 10.2.0.0/18, 10.2.64.0/18 | 10.2.128.0/24, 10.2.129.0/24 |
| 159553542841 | us-west-2 | 10.3.0.0/16 | 10.3.0.0/18, 10.3.64.0/18 | 10.3.128.0/24, 10.3.129.0/24 |

**Note**: 10.2.0.0/16 is reserved for secondary account us-east-1 expansion but not deployed at launch. Initial deployment covers main account (us-east-1 + us-west-2) and secondary account (us-west-2 only).

**Why /18 private subnets**: HyperPod EKS requires 81 IPs per P5 instance. A /18 gives 16,382 IPs — enough for ~200 P5 instances per subnet. Two subnets per VPC for AZ redundancy.

**Subnet capacity guardrails**: CloudWatch alarm on `AvailableIpAddressCount` per subnet (threshold: < 500 IPs remaining). Terraform validation: `max_gpu_nodes * 81 < subnet_size * 0.8` to prevent over-provisioning relative to subnet capacity.

**Key design decisions:**

- **VPC Peering** between accounts (not Transit Gateway). See Section 5.5 for comparison. With only 2 accounts × 2 regions = 4 peering connections, peering is simpler and has no hourly cost. Reassess if a third account is added.
- **EFA security group**: One per VPC, shared across all cluster types. Rule: `protocol -1, self-referencing` (all traffic to/from members of the SG). This is the single most critical networking rule — without it, NCCL collectives fail silently.
- **Placement groups**: One `cluster` placement group per GPU fleet per AZ. ParallelCluster creates its own; EKS node groups and HyperPod reference the shared one.
- **NAT Gateway**: One per AZ for production, single NAT for dev (cost savings).

**Terraform module**: `terraform-aws-modules/vpc/aws` v6.x

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "ml-${var.account_name}-${var.aws_region}"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  one_nat_gateway_per_az = var.is_production
  single_nat_gateway     = !var.is_production

  enable_dns_hostnames = true
  enable_dns_support   = true
}
```

#### 4.3.2 Storage

**FSx for Lustre** — High-performance training data and checkpoints:

- **Deployment type**: PERSISTENT_2 (durable, flexible throughput)
- **Throughput**: 500 MB/s/TiB for training, 250 MB/s/TiB for inference
- **S3 DRA**: Each FSx filesystem associates with the local S3 replica bucket via `aws_fsx_data_repository_association`. This means clusters read training data from FSx (fast) while S3 replication keeps the data current.
- **One FSx per account/region**: FSx Lustre does not support cross-account mounting. Each account/region gets its own filesystem populated from its S3 replica.
- **Compression**: LZ4 enabled (typically 2-3x compression on text/tokenized data, reducing storage costs with negligible CPU overhead).

**EFS** — Shared home directories and configs:

- **Throughput mode**: Elastic (auto-scales)
- **Performance mode**: generalPurpose
- **Access points**: One per team or project for isolation
- **Cross-cluster**: All three cluster types can mount the same EFS (ParallelCluster via SharedStorage YAML, EKS via EFS CSI driver, HyperPod via EFS CSI on EKS orchestrator).

**S3** — Central data hub (see Section 4.6 for replication design).

#### 4.3.3 IAM and KMS

**KMS**: One shared key per account/region for encrypting FSx, EFS, EBS, S3, and ECR. Cross-account key policy grants `kms:Encrypt`/`kms:Decrypt` to the secondary account for accessing replicated data.

**IAM Roles per cluster type:**

| Role | Cluster Type | Key Permissions |
|------|-------------|-----------------|
| `ParallelClusterHeadNodeRole` | ParallelCluster | EC2, DynamoDB, S3, CloudFormation, IAM:PassRole |
| `ParallelClusterComputeRole` | ParallelCluster | DynamoDB (Query/GetItem), S3 (GetObject), EC2 (Describe) |
| `EKSClusterRole` | EKS | EKS service-linked |
| `EKSNodeRole` | EKS | EC2, ECR, EKS (DescribeCluster) |
| `KarpenterNodeRole` | EKS (Karpenter) | EC2 (RunInstances, TerminateInstances), pricing |
| `HyperPodExecutionRole` | HyperPod | `AmazonSageMakerClusterInstanceRolePolicy`, `AmazonSageMakerHyperPodServiceRolePolicy`, S3, FSx, CloudWatch Logs |
| `TerraformExecutionRole` | CI/CD | AdministratorAccess (scoped by SCPs if in AWS Org) |
| `TerraformCIRole` | GitHub Actions | `sts:AssumeRole` to TerraformExecutionRole in both accounts |

**Cross-account pattern**: GitHub Actions OIDC → `TerraformCIRole` (main account) → `assume_role` → `TerraformExecutionRole` (target account). No long-lived credentials.

#### 4.3.4 ECR

- Single ECR registry in main account (483026362307, us-east-1)
- Cross-account pull: ECR repository policy grants full pull permissions to secondary account (`ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`, `ecr:BatchCheckLayerAvailability`). Secondary account node roles also need `ecr:GetAuthorizationToken` (resource: `*`).
- `image_tag_mutability = "IMMUTABLE"` for training reproducibility
- Lifecycle policy: Keep last 30 images per repository

### 4.4 Layer 2: Cluster Orchestration

#### 4.4.1 AWS ParallelCluster

**Terraform provider**: `aws-tf/aws-parallelcluster` v1.1.0

**Bootstrap dependency**: The ParallelCluster API (API Gateway + Lambda) must be deployed before clusters can be managed. The `aws-tf/parallelcluster/aws` module handles this via its `pcluster_api` submodule. This is a one-time setup per account/region.

**Module design** (`modules/parallelcluster/`):

```hcl
# Wraps aws-tf/parallelcluster/aws with our conventions
module "pcluster" {
  source  = "aws-tf/parallelcluster/aws"
  version = "~> 1.1"

  region              = var.region
  api_stack_name      = "pcluster-api-${var.region}"
  deploy_pcluster_api = var.deploy_api  # true only on first deploy
  cluster_configs     = var.cluster_configs
}
```

**Cluster config** (YAML in `cluster-configs/parallelcluster/`):

```yaml
Region: us-east-1
Image:
  Os: ubuntu2204
HeadNode:
  InstanceType: m5.xlarge
  Networking:
    SubnetId: ${head_node_subnet_id}
  Iam:
    AdditionalIamPolicies:
      - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
Scheduling:
  Scheduler: slurm
  ScalingStrategy: best-effort
  SlurmQueues:
    - Name: gpu-ondemand
      CapacityType: ONDEMAND
      ComputeResources:
        - Name: p5-nodes
          InstanceType: p5.48xlarge
          MinCount: 0
          MaxCount: 32
          Efa:
            Enabled: true
          HealthChecks:
            Gpu:
              Enabled: true
      Networking:
        SubnetIds:
          - ${compute_subnet_id}
        PlacementGroup:
          Enabled: true
    - Name: gpu-capacity-block
      CapacityType: CAPACITY_BLOCK
      ComputeResources:
        - Name: p5-reserved
          InstanceType: p5.48xlarge
          MinCount: 8
          MaxCount: 8
          CapacityReservationTarget:
            CapacityReservationId: ${capacity_reservation_id}
          Efa:
            Enabled: true
          HealthChecks:
            Gpu:
              Enabled: true
      Networking:
        SubnetIds:
          - ${compute_subnet_id}
        PlacementGroup:
          Enabled: true
SharedStorage:
  - Name: fsx-training
    StorageType: FsxLustre
    MountDir: /fsx
    FsxLustreSettings:
      FileSystemId: ${fsx_filesystem_id}
  - Name: efs-home
    StorageType: Efs
    MountDir: /home
    EfsSettings:
      FileSystemId: ${efs_filesystem_id}
```

#### 4.4.2 Amazon EKS

**Terraform module**: `terraform-aws-modules/eks/aws` v21.15.1

**Module design** (`modules/eks-cluster/`):

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # EKS managed add-ons (day-0 critical)
  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }  # Required for HyperPod EKS + Atlantis Pod Identity
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    aws-ebs-csi-driver = { most_recent = true }
  }

  # GPU nodes are managed exclusively by Karpenter (see NodePool below).
  # Do NOT add GPU managed node groups here to avoid dual autoscaling conflicts.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.xlarge"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
  }

  enable_efa_support = true
}
```

**Add-ons via ArgoCD** (not Terraform — see Section 4.5):

The following are managed by ArgoCD after the GitOps Bridge handoff:
- Karpenter (NodePools + EC2NodeClasses)
- NVIDIA device plugin
- EFA device plugin
- AWS Load Balancer Controller
- Metrics Server
- Cert-Manager
- External Secrets Operator
- DCGM Exporter
- Prometheus + Grafana

**Karpenter NodePool for GPU** (in `gitops/add-ons/`):

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu-training
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "reserved"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["p"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["4"]
      taints:
        - key: nvidia.com/gpu
          effect: NoSchedule
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: gpu-training
  limits:
    nvidia.com/gpu: 256
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30m
```

#### 4.4.3 SageMaker HyperPod

**Terraform provider**: `hashicorp/awscc` (resource: `awscc_sagemaker_cluster`)

No official Terraform module exists. We build a custom module (`modules/hyperpod/`) that wraps:
1. `awscc_sagemaker_cluster` — the HyperPod cluster itself
2. `aws_s3_object` — lifecycle scripts uploaded to S3
3. `aws_iam_role` — HyperPod execution role (if not passed in)

**Module design** (`modules/hyperpod/`):

```hcl
resource "awscc_sagemaker_cluster" "this" {
  cluster_name  = var.cluster_name
  node_recovery = "Automatic"

  orchestrator = var.orchestrator_type == "slurm" ? {
    slurm = { slurm_config_strategy = "Managed" }
  } : {
    eks = { cluster_arn = var.eks_cluster_arn }
  }

  vpc_config = {
    subnets            = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  instance_groups = var.instance_groups

  tags = [for k, v in var.tags : { key = k, value = v }]
}

# Upload lifecycle scripts to S3
resource "aws_s3_object" "lifecycle_scripts" {
  for_each = fileset("${var.lifecycle_scripts_path}", "**")

  bucket = var.lifecycle_scripts_bucket
  key    = "${var.lifecycle_scripts_s3_prefix}/${each.value}"
  source = "${var.lifecycle_scripts_path}/${each.value}"
  etag   = filemd5("${var.lifecycle_scripts_path}/${each.value}")
}
```

**HyperPod EKS Prerequisites** (validated in module):
- EKS cluster version must be in HyperPod's supported range (currently 1.28-1.33; verify against [AWS docs](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-eks-prerequisites.html) at implementation time)
- Authentication mode must be `API` or `API_AND_CONFIG_MAP` (not `CONFIG_MAP` only)
- VPC CNI add-on >= v1.18.4 (required for EFA)
- Amazon EKS Pod Identity Agent add-on must be installed
- The HyperPod module validates these via `precondition` blocks before creating the cluster

**HyperPod with EKS orchestrator** requires two-phase deployment:
1. Phase 1: Deploy EKS cluster via `modules/eks-cluster/` (uses `hashicorp/aws`)
2. Phase 2: Deploy HyperPod cluster via `modules/hyperpod/` with `orchestrator.eks.cluster_arn` pointing to phase 1's output (uses `hashicorp/awscc`)

In Terragrunt, this is modeled as two separate components with a `dependency` block:

```hcl
# live/secondary-account/us-west-2/hyperpod-eks/terragrunt.hcl
dependency "eks" {
  config_path = "../eks-training"
}

inputs = {
  orchestrator_type = "eks"
  eks_cluster_arn   = dependency.eks.outputs.cluster_arn
}
```

### 4.5 Layer 3: GitOps

#### 4.5.1 Atlantis — Terraform GitOps

**Deployment**: Atlantis runs on the EKS system cluster in main account (483026362307, us-east-1) as a Kubernetes Deployment with persistent volume for local state cache.

**`atlantis.yaml`** at repo root:

```yaml
version: 3
projects:
  # ── Main Account, us-east-1 ────────────────────
  - name: main-use1-networking
    dir: live/main-account/us-east-1/networking
    autoplan:
      when_modified: ["*.hcl", "../../../../modules/networking/**"]
      enabled: true
    execution_order_group: 1

  - name: main-use1-iam
    dir: live/main-account/us-east-1/iam
    autoplan:
      when_modified: ["*.hcl", "../../../../modules/iam/**"]
      enabled: true
    depends_on: [main-use1-networking]
    execution_order_group: 2

  - name: main-use1-shared-storage
    dir: live/main-account/us-east-1/shared-storage
    autoplan:
      when_modified: ["*.hcl", "../../../../modules/shared-storage/**"]
      enabled: true
    depends_on: [main-use1-networking]
    execution_order_group: 2

  - name: main-use1-eks-training
    dir: live/main-account/us-east-1/eks-training
    autoplan:
      when_modified: ["*.hcl", "../../../../modules/eks-cluster/**"]
      enabled: true
    depends_on: [main-use1-networking, main-use1-iam]
    execution_order_group: 3

  # ... additional projects follow same pattern
```

**Workflow**: PR opened → Atlantis runs `terragrunt plan` for affected projects → plan output posted as PR comment → reviewer approves → `atlantis apply` comment triggers apply → merge.

**IAM**: Atlantis pod uses EKS Pod Identity to assume `TerraformCIRole`, which can assume `TerraformExecutionRole` in either account.

#### 4.5.2 ArgoCD — Kubernetes GitOps

**Deployment**: ArgoCD runs on the same EKS system cluster as Atlantis (hub). It manages workloads on all EKS clusters (spokes) via the hub-spoke pattern.

**GitOps Bridge** — the handoff between Terraform and ArgoCD:

1. Terraform creates each EKS cluster (via `modules/eks-cluster/`)
2. A separate hub-only Terragrunt component (`live/{account}/{region}/argocd/terragrunt.hcl`) installs ArgoCD on the hub cluster and registers spoke clusters
3. For each spoke cluster, Terraform creates an ArgoCD cluster secret (in the hub's ArgoCD namespace) with cluster metadata annotations
4. ArgoCD reads annotations and deploys add-ons/workloads from `gitops/` directory to each spoke

**Important**: ArgoCD is installed only on the hub cluster (main account, us-east-1 EKS system cluster). It is NOT installed inside `modules/eks-cluster/` — that would give every cluster its own ArgoCD, breaking the hub-spoke model.

```hcl
# In live/main-account/us-east-1/argocd/terragrunt.hcl (hub-only component)
# Installs ArgoCD on the hub cluster
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
}

# Hub cluster registers itself
resource "kubernetes_secret" "hub_cluster" {
  metadata {
    name      = var.cluster_name
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "cluster" }
    annotations = {
      "aws_account_id"  = var.account_id
      "aws_region"      = var.region
      "aws_vpc_id"      = var.vpc_id
      "cluster_type"    = var.cluster_type
      "enable_karpenter"             = "true"
      "enable_nvidia_device_plugin"  = "true"
      "enable_efa_device_plugin"     = "true"
      "enable_dcgm_exporter"         = "true"
    }
  }
  data = {
    name   = var.cluster_name
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}

# Each spoke cluster is registered via a separate secret with the remote endpoint
resource "kubernetes_secret" "spoke_clusters" {
  for_each = var.spoke_clusters  # map of cluster_name => { endpoint, ca_data, token, annotations }

  metadata {
    name      = each.key
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "cluster" }
    annotations = each.value.annotations
  }
  data = {
    name   = each.key
    server = each.value.endpoint
    config = jsonencode({
      bearerToken = each.value.token
      tlsClientConfig = {
        insecure = false
        caData   = each.value.ca_data
      }
    })
  }
}
```

**App-of-apps** (`gitops/bootstrap/applicationset.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: '{{name}}-addons'
    spec:
      project: default
      source:
        repoURL: https://github.com/org/ml-clusters.git
        targetRevision: main
        path: gitops/add-ons
      destination:
        server: '{{server}}'
        namespace: kube-system
```

### 4.6 Layer 4: Data Distribution

**Hub-and-spoke S3 replication:**

```
Central bucket (483026362307, us-east-1)
  │
  ├─ CRR ──→ Replica (483026362307, us-west-2)       # Cross-region replication
  ├─ SRR ──→ Replica (159553542841, us-east-1)       # Same-region, cross-account replication
  └─ CRR ──→ Replica (159553542841, us-west-2)       # Cross-region, cross-account replication
```

**Data flow**: Upload data to central bucket → S3 CRR/SRR replicates to regional replicas (15 min SLA with RTC) → FSx Lustre DRA auto-imports from local S3 replica → Clusters read from FSx.

**Replication rules** (per-prefix):

| Prefix | Storage Class (replica) | RTC | Rationale |
|--------|------------------------|-----|-----------|
| `datasets/` | STANDARD | Yes | Training data needs fast, reliable sync |
| `checkpoints/` | STANDARD | Yes | Resume training from any region |
| `models/` | STANDARD_IA | No | Accessed infrequently after training |
| `code/` | STANDARD | Yes | Must be current everywhere |
| `logs/` | Not replicated | N/A | Region-specific, stored locally |

**Replication prerequisites**:
- **Versioning enabled** on both source and destination buckets (required for S3 replication)
- **S3 Batch Replication** for existing objects: S3 live replication only applies to new objects. Run a one-time S3 Batch Replication job during initial setup to replicate existing data to all replicas
- Replication status monitoring: CloudWatch metrics for `ReplicationLatency` and `OperationsPendingReplication`. Alert on `ReplicationNotReplicated` > 0 for > 30 min

**Cross-account requirements**:
- Destination bucket policy allows replication role from main account
- `access_control_translation { owner = "Destination" }` transfers ownership
- KMS: replication role needs `kms:Decrypt` on source key + `kms:Encrypt` on destination key
- S3 bucket naming: `ml-data-{account_name}-{region}` (e.g., `ml-data-main-us-east-1`, `ml-data-secondary-us-west-2`)

### 4.7 Layer 5: Capacity Management (Claude Code Skills)

Two Claude Code skills for GPU capacity procurement:

#### Skill: `capacity-blocks`

Manages EC2 Capacity Blocks for EKS and ParallelCluster workloads.

**Commands:**

| Command | Description | AWS API |
|---------|-------------|---------|
| `/capacity-blocks search` | Search available offerings | `ec2:DescribeCapacityBlockOfferings` |
| `/capacity-blocks buy` | Purchase with confirmation | `ec2:PurchaseCapacityBlock` |
| `/capacity-blocks list` | List active/scheduled blocks | `ec2:DescribeCapacityBlocks` |
| `/capacity-blocks status` | Check utilization | `ec2:DescribeCapacityBlockStatus` |
| `/capacity-blocks extend` | Search + purchase extensions | `ec2:DescribeCapacityBlockExtensionOfferings` + `ec2:PurchaseCapacityBlockExtension` |

**Example interaction:**
```
User: /capacity-blocks search --type p5.48xlarge --count 8 --days 7 --region us-east-1

Claude: Found 3 offerings for 8x p5.48xlarge (7 days) in us-east-1:

  AZ           Start              End                Price
  us-east-1a   2026-03-05 00:00   2026-03-12 00:00   $45,230.40
  us-east-1b   2026-03-06 00:00   2026-03-13 00:00   $45,230.40
  us-east-1a   2026-03-10 00:00   2026-03-17 00:00   $44,890.20

  Purchase one? Specify the row number (cost is charged upfront).
```

**Post-purchase integration**: After purchasing, the skill outputs the `CapacityReservationId`. The user then:
- For **EKS**: Updates the Karpenter EC2NodeClass `capacityReservationSelectorTerms` in `gitops/`
- For **ParallelCluster**: Sets `CapacityReservationTarget.CapacityReservationId` in cluster config YAML
- Both changes go through the normal PR → Atlantis/ArgoCD flow

#### Skill: `training-plans`

Manages SageMaker Training Plans for HyperPod workloads.

**Commands:**

| Command | Description | AWS API |
|---------|-------------|---------|
| `/training-plans search` | Search offerings | `sagemaker:SearchTrainingPlanOfferings` |
| `/training-plans buy` | Purchase with confirmation | `sagemaker:CreateTrainingPlan` |
| `/training-plans list` | List active plans | `sagemaker:ListTrainingPlans` |
| `/training-plans status` | Check utilization | `sagemaker:DescribeTrainingPlan` |

**Key difference from Capacity Blocks**: Training Plans require specifying `--target` (training-job, hyperpod-cluster, or endpoint) at search time. The AZ of the plan determines which subnet the HyperPod cluster must use.

**Cross-account limitation**: Training Plans cannot be shared across accounts. Each plan must be purchased and consumed in the same account. The skill must prompt for `--account` and assume the correct role before making API calls.

**Post-purchase integration**: The `TrainingPlanArn` is added to the HyperPod instance group config in Terragrunt and applied via Atlantis.

### 4.8 Layer 6: Observability

**Strategy**: Unified metrics pipeline using Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG), supplemented by CloudWatch for service-level metrics.

| Cluster Type | GPU Metrics | System Metrics | Logs |
|---|---|---|---|
| ParallelCluster | DCGM Exporter → Prometheus | Node Exporter → Prometheus | CloudWatch Logs (auto) |
| EKS | DCGM Exporter DaemonSet → AMP | Container Insights / Node Exporter → AMP | FluentBit → CloudWatch |
| HyperPod (Slurm) | Health Monitoring Agent → CloudWatch | CloudWatch | CloudWatch `/aws/sagemaker/Clusters/` |
| HyperPod (EKS) | Health Monitoring Agent + DCGM → CloudWatch | CloudWatch + Node Exporter | CloudWatch |

**Dashboards** (AMG):
1. **Fleet Overview**: GPU utilization, EFA bandwidth, storage IOPS across all clusters
2. **Per-Cluster**: Node health, job queue depth, GPU memory usage
3. **Capacity**: Capacity Block utilization, Training Plan status, on-demand vs reserved usage
4. **Cost**: Per-cluster hourly cost estimates (CloudWatch metrics + tag-based allocation)

**Alerting**:
- GPU utilization < 10% for > 30 min → idle instance alert
- EFA errors > threshold → network health alert
- FSx Lustre IOPS > 80% capacity → storage bottleneck alert
- Capacity Block expiry < 24 hours → renewal reminder
- HyperPod deep health check failure → auto-remediation tracking

---

## 5. Alternatives Considered

### 5.1 Crossplane Instead of Terraform for Infrastructure

**Crossplane v2.2** (CNCF graduated) would let us define all AWS resources as Kubernetes CRDs, managed by ArgoCD with continuous reconciliation.

| | Terraform + Terragrunt | Crossplane + ArgoCD |
|---|---|---|
| **Drift detection** | Scheduled `terraform plan` | Continuous reconciliation (auto-corrects) |
| **Provider coverage** | Full AWS coverage (hashicorp/aws is best-in-class) | Good but not complete (`provider-upjet-aws`) |
| **ParallelCluster** | Dedicated provider exists | No Crossplane provider — would need custom controller |
| **HyperPod** | AWSCC provider works | No Crossplane provider |
| **Learning curve** | Terraform widely known | K8s CRD model unfamiliar to some |
| **State** | Explicit (S3) | Implicit (K8s etcd) — harder to inspect/debug |

**Decision**: Terraform + Terragrunt. Crossplane lacks providers for ParallelCluster and HyperPod, which are 2 of our 3 cluster types. Crossplane's continuous reconciliation is attractive, but not worth building custom controllers.

### 5.2 Spacelift Instead of Atlantis for Terraform GitOps

| | Atlantis | Spacelift |
|---|---|---|
| **Cost** | Free (self-hosted) | $0.60/managed resource/month (hundreds of resources = hundreds of dollars) |
| **Hosting** | Self-hosted on our EKS | SaaS |
| **Terragrunt support** | Yes (via wrapper) | Yes (native) |
| **Drift detection** | Manual (cron job) | Built-in scheduled drift detection |
| **Stack dependencies** | Manual (`depends_on` in atlantis.yaml) | Native DAG with auto-triggering |
| **Policy** | Manual (pre/post hooks) | Built-in OPA policy engine |
| **Operational burden** | We maintain it | Zero |

**Decision**: Atlantis for now. Self-hosted keeps costs low and we maintain full control. The operational overhead of running Atlantis on EKS is minimal (single pod, persistent volume). If drift detection or stack dependencies become pain points, re-evaluate Spacelift.

### 5.3 Terraform Workspaces Instead of Directory-Based Environments

| | Workspaces | Directories (chosen) |
|---|---|---|
| **Isolation** | Weak (same config, different state) | Strong (separate configs, separate state) |
| **Account differences** | Requires conditionals everywhere | Natural per-account `account.hcl` |
| **Structural divergence** | Hard (e.g., HyperPod only in secondary) | Easy (just add/remove dirs) |
| **Visibility** | `terraform workspace list` (invisible in repo) | `ls live/` (visible in repo) |

**Decision**: Directories. Our two accounts have different cluster compositions (main has ParallelCluster, secondary has HyperPod). Workspaces assume identical structure, which doesn't match our reality.

### 5.4 Single EKS Cluster Per Account vs Multiple

| | Single large EKS | Multiple specialized EKS (chosen) |
|---|---|---|
| **Blast radius** | One bad upgrade affects all workloads | Isolated per-cluster |
| **K8s version** | Single version for everything | Per-cluster version (training can lag, inference stays current) |
| **Karpenter limits** | Shared GPU limits across workloads | Per-cluster GPU limits |
| **Operational overhead** | Less | More clusters to manage (mitigated by Terraform/ArgoCD) |

**Decision**: Multiple EKS clusters (training, inference). Training clusters can run older K8s versions for stability. Inference clusters can upgrade independently. ArgoCD hub-spoke makes multi-cluster management manageable.

### 5.5 VPC Peering vs Transit Gateway

| | VPC Peering (chosen) | Transit Gateway |
|---|---|---|
| **Cost** | Free (no hourly, no data processing) | $0.05/GB data processing + $36/month/attachment |
| **Connections** | Point-to-point (N×(N-1)/2 for N VPCs) | Hub-and-spoke (N connections) |
| **Routing complexity** | Simple for 2 accounts × 2 regions = 4 peerings | Simpler at scale (centralized route tables) |
| **Transitive routing** | No (each peering is direct) | Yes (any-to-any via TGW) |
| **Bandwidth** | No limit (uses AWS backbone) | Up to 50 Gbps per attachment |
| **Cross-region** | Supported | Supported (inter-region peering) |

**Decision**: VPC Peering. With 4 VPCs (2 accounts × 2 regions), we need at most 4 peering connections (intra-region cross-account pairs + any needed cross-region links). Transit Gateway's per-GB cost on GPU training data transfers would be significant. Reassess when adding a third account or third region where peering complexity grows as O(N²).

### 5.6 AWS PCS Instead of ParallelCluster for Slurm

AWS Parallel Computing Service (PCS) is a fully managed Slurm service (distinct from ParallelCluster, which is self-managed). PCS gained Terraform support in March 2025.

| | ParallelCluster (chosen) | AWS PCS |
|---|---|---|
| **Management** | Self-managed (head node is an EC2 instance) | Fully managed (no head node to maintain) |
| **Terraform** | Official provider + module (mature) | `aws_pcs_cluster` in hashicorp/aws (newer) |
| **Customization** | Full control (custom AMIs, packages, Slurm config) | Limited (managed service constraints) |
| **Capacity Blocks** | Supported (CapacityType: CAPACITY_BLOCK) | Supported natively |
| **EFA** | Supported | Supported |
| **Slurm version** | Choose version (via ParallelCluster version) | AWS-managed version |
| **Cost** | No service fee (pay for EC2 only) | No service fee (pay for EC2 only) |

**Decision**: ParallelCluster for now. The team has existing ParallelCluster experience, and the Terraform module is more mature. PCS reduces operational overhead (no head node) but limits customization. If head node management becomes a burden, migrate individual clusters to PCS — both use Slurm, so job scripts are portable.

---

## 6. Operational Considerations

### 6.1 Failure Modes

| Failure | Impact | Detection | Recovery |
|---------|--------|-----------|----------|
| **GPU failure (XID error)** | Training job crashes | DCGM alert; HyperPod Health Monitoring Agent | ParallelCluster: manual drain. HyperPod: auto-replace. EKS: Karpenter replaces node. |
| **EFA degradation** | NCCL collectives slow or fail | EFA latency/bandwidth alerts | Replace affected node. Check placement group. |
| **FSx Lustre outage** | All clusters in region lose fast storage | CloudWatch FSx metrics | Fallback to S3 direct reads (slower). FSx is replicated within AZ. |
| **S3 replication lag** | Clusters read stale data | CloudWatch S3 replication metrics | Check RTC compliance. For critical data, wait for replication or `s3 sync` manually. |
| **Atlantis down** | Cannot apply TF changes | Kubernetes pod health check | Restart pod. State is in S3, not on Atlantis. Manual `terragrunt apply` as fallback. |
| **ArgoCD down** | K8s workloads still run (no new deploys) | ArgoCD health check | Restart. K8s reconciliation resumes. No data loss. |
| **Capacity Block expires** | Instances terminate 30 min before end | Alerting 24h before expiry | Extend via `/capacity-blocks extend` or migrate workload. |
| **Terraform state corruption** | Cannot plan/apply | `terraform plan` fails | Restore from S3 versioning. This is why versioning is mandatory. |
| **Cross-account role assumption fails** | Cannot deploy to secondary account | `terraform plan` fails for secondary | Check STS, role trust policy, session duration. |
| **Subnet IP exhaustion** | New nodes fail to launch | CloudWatch `AvailableIpAddressCount` alarm | Add subnet or reduce max nodes. HyperPod EKS uses 81 IPs/P5. |
| **HyperPod EKS prerequisite drift** | HyperPod operations fail after EKS upgrade | HyperPod API returns validation error | Roll back EKS version or update to next supported version. |
| **S3 replication permanent failure** | Clusters read stale data indefinitely | S3 replication metrics show `FAILED` status | Investigate failed objects via S3 inventory report. Re-run S3 Batch Replication for failed objects. |

**Break-glass procedures** (when Atlantis/ArgoCD are unavailable):

1. **Atlantis down**: Clone repo locally → `aws sts assume-role` for target account → `terragrunt plan` / `terragrunt apply` from the `live/` directory. State is in S3, not on Atlantis.
2. **ArgoCD down**: Running K8s workloads continue unaffected. For urgent changes: `kubectl apply -f` directly. ArgoCD will reconcile when restored (may show "OutOfSync" then auto-sync).
3. **Both down**: EKS system cluster is unhealthy. Use `terraform output` from networking/eks state to get cluster endpoint → `aws eks update-kubeconfig` → debug EKS directly.

### 6.2 Rollout Strategy

**Phase 1 — Foundation (Week 1-2)**:
1. Bootstrap Terraform state bucket and IAM roles (manual one-time setup)
2. Deploy `networking` module in both accounts (VPCs, subnets, SGs)
3. Deploy `iam` module (all IAM roles, KMS keys)
4. Deploy `s3-central-data` and replicas, run S3 Batch Replication for existing objects

**Phase 2 — Storage + First Cluster (Week 3-4)**:
1. Deploy `shared-storage` (FSx Lustre, EFS) in primary region
2. Deploy first EKS cluster in main account
3. Install ArgoCD, validate GitOps Bridge
4. Deploy Atlantis on EKS
5. Migrate all subsequent changes to PR-based workflow

**Phase 3 — Multi-Cluster (Week 5-6)**:
1. Deploy ParallelCluster in main account
2. Deploy HyperPod in secondary account
3. Deploy second EKS cluster (inference or secondary account)
4. Validate cross-account S3 replication + FSx DRA

**Phase 4 — Skills + Polish (Week 7-8)**:
1. Build and test Claude Code skills (`capacity-blocks`, `training-plans`)
2. Deploy observability stack (AMP, AMG, dashboards)
3. Set up drift detection (scheduled `terraform plan`)
4. Documentation and team onboarding

### 6.3 Day-2 Operations

**Adding a new region**: Create `live/{account}/new-region/` with `region.hcl`, add networking + storage + cluster terragrunt.hcl files. Add S3 replication rule. PR → review → apply.

**Adding a new cluster**: Add terragrunt.hcl in the appropriate account/region directory. For EKS, ArgoCD auto-discovers via cluster secret. PR → review → apply.

**Upgrading EKS version**: Update `cluster_version` in the eks-cluster module input. Atlantis shows the plan. Apply updates control plane, then update node groups. ArgoCD continues to work across versions.

**Upgrading ParallelCluster version**: Update the cluster config YAML and module version. ParallelCluster performs rolling update of compute fleet. Head node may require stop/start.

---

## 7. Security and Cost

### 7.1 Security

- **No long-lived credentials**: GitHub Actions OIDC → STS → short-lived session tokens
- **Least privilege**: Each cluster type has its own IAM role with minimum required permissions
- **Encryption at rest**: All storage (S3, FSx, EFS, EBS, ECR) encrypted with KMS
- **Encryption in transit**: EFS encryption in transit enabled; S3 enforces `aws:SecureTransport`
- **Network isolation**: Private subnets for all compute; NAT gateway for outbound only
- **EFA traffic**: Self-referencing SG only — no `0.0.0.0/0` outbound (breaks EFA health checks on HyperPod)
- **ECR immutable tags**: Prevents training image modification after push
- **Policy as code**: Checkov v3.x in CI pipeline for static analysis of Terraform configs
- **State locking**: S3 native locking via `use_lockfile = true` (Terraform 1.10+, DynamoDB deprecated). Lock recovery: if a lock gets stuck, delete the `.tflock` object from S3 after confirming no active apply is running
- **State security**: S3 state bucket encrypted, versioned, public access blocked, access via IAM only

### 7.2 Cost Considerations

**Major cost drivers (ordered by magnitude):**

1. **GPU instances**: P5.48xlarge = ~$98/hr on-demand. Capacity Blocks may be cheaper depending on supply/demand. This is 80-90% of total cost.
2. **FSx for Lustre**: PERSISTENT_2 at 500 MB/s/TiB ≈ $0.145/GB/month. 10 TiB = ~$1,480/month.
3. **NAT Gateway**: $0.045/hr + $0.045/GB. Cross-AZ traffic from GPU nodes can be significant. Mitigate with VPC endpoints for S3, ECR.
4. **S3 replication**: Cross-region = $0.02/GB. Cross-account adds nothing extra. Budget for 2-3x data size across replicas.
5. **EKS control plane**: $0.10/hr per cluster (~$73/month). Minimal relative to GPU costs.

**Cost controls:**
- Capacity Blocks for predictable training runs (potentially lower than on-demand)
- Karpenter `consolidationPolicy: WhenEmpty` to avoid paying for idle GPU nodes
- ParallelCluster auto-scaling (`MinCount: 0`) to scale to zero when no jobs
- S3 Intelligent-Tiering for checkpoint/model storage after initial access period
- VPC endpoints for S3 and ECR to avoid NAT Gateway data processing charges

---

## 8. Open Questions

1. **Regions**: Which regions will each account deploy clusters in? The design assumes us-east-1 and us-west-2 but this should be confirmed per capacity availability.
2. **Atlantis scaling**: With 20+ Terragrunt projects, Atlantis may need concurrent worker configuration. Monitor plan/apply queue depth.
3. **HyperPod EKS vs standalone EKS**: For the secondary account, should the EKS cluster be a standalone EKS or HyperPod EKS? HyperPod adds deep health checks and auto-resume but reduces control over node management.
4. **Slurm accounting database**: Should ParallelCluster and HyperPod Slurm clusters share a Slurm accounting database? This would enable cross-cluster job history and fairshare scheduling.
5. **Capacity Block automation**: Should the Claude Code skills automatically update Terraform configs after a purchase, or should the user manually create the PR? Automatic PR creation is possible but adds complexity.
6. **Disaster recovery**: What is the RPO/RTO for the Terraform state bucket? S3 versioning provides RPO ≈ 0, but cross-region replication of the state bucket itself is not currently planned.
7. **AWS Organizations**: Are both accounts in the same AWS Organization? If so, SCPs and RAM sharing are simpler. If not, explicit trust policies are needed everywhere.

---

## 9. References

### Terraform Providers and Modules
- `aws-tf/aws-parallelcluster` provider v1.1.0 — [Terraform Registry](https://registry.terraform.io/providers/aws-tf/aws-parallelcluster/latest)
- `aws-tf/parallelcluster/aws` module v1.1.0 — [Terraform Registry](https://registry.terraform.io/modules/aws-tf/parallelcluster/aws/latest)
- `terraform-aws-modules/eks/aws` v21.15.1 — [GitHub](https://github.com/terraform-aws-modules/terraform-aws-eks)
- `aws-ia/eks-blueprints-addons/aws` v1.23.0 — [GitHub](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons)
- `hashicorp/awscc` provider >= v1.25.0 — [Terraform Registry](https://registry.terraform.io/providers/hashicorp/awscc/latest)
- `terraform-aws-modules/vpc/aws` v6.x — [GitHub](https://github.com/terraform-aws-modules/terraform-aws-vpc)

### AWS Documentation
- [AWS ParallelCluster User Guide](https://docs.aws.amazon.com/parallelcluster/latest/ug/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [SageMaker HyperPod Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod.html)
- [EC2 Capacity Blocks for ML](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html)
- [SageMaker Training Plans](https://docs.aws.amazon.com/sagemaker/latest/dg/reserve-capacity-with-training-plans.html)
- [S3 Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)

### Tools
- [Terragrunt](https://terragrunt.gruntwork.io/) v0.99.4
- [Atlantis](https://www.runatlantis.io/) v0.40.0
- [ArgoCD](https://argo-cd.readthedocs.io/) v2.x
- [Karpenter](https://karpenter.sh/) v1.8.6
- [Checkov](https://www.checkov.io/) v3.2.x

### Patterns
- [GitOps Bridge](https://github.com/gitops-bridge-dev/gitops-bridge) — Terraform-to-ArgoCD handoff pattern
- [EKS Blueprints Hub-Spoke](https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/gitops/gitops-multi-cluster-hub-spoke-argocd/)
- [Terragrunt Multi-Account Example](https://github.com/gruntwork-io/terragrunt-infrastructure-live-example)

---

## Appendix: Codex Second Opinion

This design was reviewed by Codex (OpenAI) as a second opinion. Key findings incorporated:

| Finding | Action Taken |
|---------|-------------|
| Subnet IP exhaustion not monitored | Added CloudWatch alarms + Terraform validation guardrails (Section 4.3.1) |
| HyperPod EKS prerequisite drift | Added prerequisite validation with precondition blocks (Section 4.4.3) |
| S3 Batch Replication for existing objects | Added to replication design + rollout plan (Sections 4.6, 6.2) |
| Break-glass procedure missing | Added manual fallback procedures (Section 6.1) |
| AWS PCS not considered | Added as Alternative 5.6 with comparison |
| VPC Peering vs TGW not analyzed | Added as Alternative 5.5 with cost/complexity comparison |
| Training Plans cross-account limitation | Documented constraint in skill design (Section 4.7) |
| EKS module requires AWS provider v6.x | Fixed provider version from v5.x to v6.x throughout |
| CIDR table vs repo layout mismatch | Marked secondary us-east-1 as "reserved" with note |

Rejected finding: Codex suggested HyperPod Slurm may not be supported in AWSCC provider. Verified that CloudFormation `AWS::SageMaker::Cluster` supports both `Slurm` and `Eks` orchestrator types, and AWSCC provider mirrors the CloudFormation schema.

## Appendix: Lieutenant Review (Claude + Codex Reconciled)

Second review pass with Terraform registry verification and AWS docs cross-checking. 8 must-fix issues found and resolved:

| Finding | Action Taken |
|---------|-------------|
| VPC module v5.x outdated (v6.6.0 available) | Updated to `~> 6.0` (Section 4.3.1, References) |
| HyperPod EKS K8s version range wrong ("1.30-1.32") | Corrected to "1.28-1.33" with link to AWS docs (Section 4.4.3) |
| ECR cross-account permissions incomplete (only `BatchGetImage`) | Added full pull permission set including `GetDownloadUrlForLayer`, `BatchCheckLayerAvailability`, `GetAuthorizationToken` (Section 4.3.4) |
| EKS Pod Identity Agent add-on missing from day-0 set | Added `eks-pod-identity-agent` to `cluster_addons` (Section 4.4.2) |
| ArgoCD installed in every EKS cluster, not hub-only; cluster secret hardcoded to local | Moved ArgoCD to hub-only component (`argocd/terragrunt.hcl`), added spoke registration with remote endpoints (Section 4.5.2) |
| Dual GPU autoscaling via managed node groups + Karpenter | Removed GPU managed node group; Karpenter exclusively manages GPU nodes (Section 4.4.2) |
| S3 replication to secondary us-east-1 mislabeled as CRR (same-region) | Corrected to SRR with annotation (Section 4.6) |
| Capacity Block duration limits incorrect in research report | Updated to "1-182 days" with AWS docs link (research report) |
