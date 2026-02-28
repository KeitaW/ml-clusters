# Research Report: AWS ML Cluster Management with GitOps + Terraform

**Date**: 2026-02-28
**Version scope**: ParallelCluster 3.x, EKS 1.29-1.34, SageMaker HyperPod (GA), Terraform 1.14.x
**Confidence**: High (primary sources consulted for all major findings)

---

## Executive Summary

This report synthesizes research across 6 parallel streams covering AWS ParallelCluster, Amazon EKS, SageMaker HyperPod, GitOps patterns, shared infrastructure, and multi-cluster Terraform patterns. The goal is to inform a design doc for managing all three cluster types with GitOps + Terraform.

**Key findings:**
1. All three cluster types have Terraform support, but through **different providers** (aws-tf/aws-parallelcluster, hashicorp/aws for EKS, hashicorp/awscc for HyperPod)
2. A **directory-based monorepo with Terragrunt** is the recommended structure for multi-cluster management
3. **GitOps Bridge pattern** (Terraform provisions infra + ArgoCD manages K8s workloads) is the recommended GitOps approach for EKS
4. Shared infrastructure (VPC, FSx Lustre, EFS, IAM, monitoring) can be unified across all cluster types
5. **Atlantis** is the recommended GitOps tool for Terraform PR workflows
6. **Multi-account deployment** uses Terragrunt `account.hcl` + provider `assume_role` with central state in main account (483026362307)
7. **S3 cross-region/cross-account replication** supports hub-and-spoke data distribution from central us-east-1 bucket to per-cluster-region replicas

**Account topology:**
- **Main account (483026362307)**: Management + workload. Hosts Terraform state bucket, central S3 data bucket (us-east-1), ECR registry, and ML clusters
- **Secondary account (159553542841)**: Workload only. Additional ML clusters, receives S3 data replicas

---

## 1. AWS ParallelCluster

### Terraform Support

**Provider**: `aws-tf/aws-parallelcluster` (dedicated provider, NOT in hashicorp/aws)
- Registry: https://registry.terraform.io/providers/aws-tf/aws-parallelcluster/latest
- Provider v1.0.0 → ParallelCluster 3.8.0-3.10.1
- Provider v1.1.0 → ParallelCluster 3.11.0+
- Minimum Terraform: 1.5.7

**Resources**: `aws-parallelcluster_cluster`, `aws-parallelcluster_image`

**Critical prerequisite**: The ParallelCluster API (API Gateway + Lambda) must be deployed first. The provider communicates through this API, not directly with AWS APIs.

**Official Terraform Module**: `aws-tf/parallelcluster/aws` v1.1.0
- Three submodules: `pcluster_api` (deploys API), `required_infra` (VPC/subnets), `clusters` (manages clusters)
- Accepts config as HCL objects, JSON, or YAML file paths

### Configuration

ParallelCluster v3 uses YAML config with key sections:
- `HeadNode`: Instance type, networking, SSH, IAM, custom actions
- `Scheduling`: Slurm queues, compute resources, scaling strategy
- `SharedStorage`: Up to 20 EFS + 20 FSx filesystems (v3.2.0+)
- `CustomActions`: OnNodeStart, OnNodeConfigured, OnNodeUpdated (v3.4.0+)

### GPU/Accelerator Support

- Supports p4d, p4de, p5, p5e, p5en, g4dn, g5, trn1/trn2
- EFA auto-configured with `Efa.Enabled: true` + mandatory placement group
- Slurm GRES auto-generated (`gres.conf`) — GPU type detected automatically
- GPU health checks via DCGM (`HealthChecks.Gpu.Enabled: true`)
- OSS NVIDIA drivers + EFA 1.29.0+ installed by default (v3.8.0+)

### Slurm Integration

- Multi-queue with multiple compute resources per queue
- Multiple instance types per compute resource (v3.3.0+, same vCPU/accelerator count)
- `CustomSlurmSettings` at cluster/queue/node level (v3.6.0+)
- Capacity types: ONDEMAND, SPOT, CAPACITY_BLOCK
- Slurm accounting database support
- Scaling strategies: all-or-nothing, greedy-all-or-nothing, best-effort

### Key Version Notes

| Feature | Min Version |
|---------|------------|
| Terraform support | 3.8.0 |
| Multi-filesystem (20+20) | 3.2.0 |
| Multiple instance types per CR | 3.3.0 |
| OnNodeUpdated hook | 3.4.0 |
| CustomSlurmSettings | 3.6.0 |
| FSx File Cache | 3.7.0 |
| IMDSv2 default | 3.7.0 |
| OSS NVIDIA drivers default | 3.8.0 |

**Sources (Tier 1)**: AWS ParallelCluster docs, Terraform Registry, GitHub aws-tf/terraform-provider-aws-parallelcluster

---

## 2. Amazon EKS

### Terraform Support

**Module**: `terraform-aws-modules/eks/aws` v21.15.1
- Terraform >= 1.3, AWS Provider >= 5.34
- Managed node groups, self-managed node groups, Fargate profiles
- EKS Auto Mode support (v20.31+)
- Pod Identity default (IRSA removed in v21.0)
- EFA support built-in (`enable_efa_support = true`)
- Karpenter sub-module for IAM/SQS

**Add-ons Module**: `aws-ia/eks-blueprints-addons/aws` v1.23.0
- 30+ add-ons: ALB Controller, Karpenter, Cert-Manager, ArgoCD, External Secrets, etc.
- Manages both EKS native add-ons and Helm-based add-ons

**Blueprints**: `aws-ia/terraform-aws-eks-blueprints` v5.0.0
- Reference patterns (not a consumable module)
- GPU/EFA, GitOps, multi-cluster hub-spoke patterns

### GPU/Accelerator Node Groups

| Instance | AMI Type | Device Plugin | EFA |
|----------|----------|--------------|-----|
| p4d/p5/p5e | AL2023_x86_64_NVIDIA | NVIDIA k8s-device-plugin v0.17.1 | Yes |
| trn1/trn2/inf2 | AL2023_x86_64_NEURON | AWS Neuron Helm Chart | Yes |
| g5/g6 | AL2023_x86_64_NVIDIA | NVIDIA k8s-device-plugin | No |

EFA requires: VPC CNI v1.18.4+, cluster placement group, self-referencing SG rules.

### Karpenter (v1.8.6)

- API stable at `karpenter.sh/v1`
- NodePool + EC2NodeClass for GPU workloads
- Capacity types: on-demand, spot, reserved (ODCRs)
- GPU scheduling labels: `instance-gpu-name`, `instance-gpu-memory`, `instance-gpu-count`
- Disruption policies: WhenEmpty recommended for training (avoid preempting jobs)
- ODCR support via `capacityReservationSelectorTerms` in EC2NodeClass

### GitOps Patterns

**ArgoCD (recommended for K8s workloads)**:
- GitOps Bridge pattern: Terraform provisions infra → writes metadata to ArgoCD cluster secret → ArgoCD manages add-ons/workloads from Git
- App-of-apps pattern for bootstrapping
- Module: `gitops-bridge-argocd-bootstrap-terraform`

**Flux**:
- Terraform provider: `fluxcd/flux` v1.8.1
- `flux_bootstrap_git` resource commits manifests to Git + installs on cluster
- Kustomization overlays for multi-cluster/multi-env
- `substituteFrom` to pass Terraform outputs via ConfigMap

**Hybrid approach (recommended)**:
- Terraform manages: VPC, EKS cluster, IAM roles, Pod Identity, EKS native add-ons (CoreDNS, VPC CNI, kube-proxy)
- GitOps (ArgoCD) manages: Helm-based add-ons, Karpenter NodePools, application workloads

### Multi-Cluster EKS

- Hub-spoke with ArgoCD: Hub cluster hosts ArgoCD, manages spoke clusters
- Cross-cluster communication via VPC Lattice
- Each cluster has its own Terraform state

**Sources (Tier 1)**: terraform-aws-eks GitHub, EKS Blueprints docs, Karpenter docs, ArgoCD docs

---

## 3. SageMaker HyperPod

### Terraform Support

**Provider**: `hashicorp/awscc` (NOT hashicorp/aws)
- Resource: `awscc_sagemaker_cluster`
- Added: September 10, 2024
- Min provider version: v1.23.0

**No official Terraform module exists.** AWS provides CloudFormation templates via `aws/sagemaker-hyperpod-cluster-setup`.

### Slurm Orchestrator

- Node types: Controller, Login, Compute
- `SlurmConfigStrategy`: Managed (recommended), Overwrite, Merge
- Slurm v23.11.3 (with slurmrestd)
- Auto-resume: `srun --auto-resume=1` for fault-tolerant training

### EKS Orchestrator (added September 2024)

- 1-to-1 mapping: Create EKS cluster first, then HyperPod attaches via `ClusterArn`
- K8s versions: 1.28-1.34
- Key differentiators vs standalone EKS: deep health checks, auto-resume, automatic faulty node replacement, HyperPod-managed AMIs
- `KubernetesConfig`: Labels and taints per instance group
- `NodeProvisioningMode: Continuous` for EKS

### Deep Health Checks

- Instance-level: GPU/NVLink count, DCGM Level 4, Neuron checks, EFA latency/bandwidth
- Cluster-level: NCCL test (cross-node collectives), NCCOM cluster test
- API enums: `InstanceStress`, `InstanceConnectivity`
- Continuous monitoring via Health Monitoring Agent (GPU count validation, NVLink errors, EFA failures)
- Automatic remediation: node replacement when faults detected

### Lifecycle Scripts

- Stored in S3 (bucket name must start with `sagemaker-`)
- `on_create.sh` as entrypoint
- `provisioning_parameters.json` for legacy config (API-driven config recommended)
- Base scripts: `aws-samples/awsome-distributed-training` repo
- Runtime metadata: `/opt/ml/config/resource_config.json`

### Storage

| Type | Config |
|------|--------|
| EBS | `InstanceStorageConfigs.EbsVolumeConfig` |
| FSx Lustre | `InstanceStorageConfigs.FsxLustreConfig` (dns_name, mount_path) |
| FSx OpenZFS | `InstanceStorageConfigs.FsxOpenZfsConfig` |
| Tiered Storage | `TieredStorageConfig` (checkpoint management) |

### Networking

- VPC mandatory for EKS orchestrator, optional for Slurm (required if using FSx)
- Per-instance-group VPC override via `OverrideVpcConfig` (Feb 2025)
- Subnet sizing: Slurm+P5 = 32 IPs/instance, EKS+P5 = 81 IPs/instance
- EFA SG: all traffic self-referencing, do NOT use 0.0.0.0/0 outbound
- Multi-AZ support (Nov 2024), IPv6 support (Jan 2025)

### Key Timeline

| Date | Milestone |
|------|-----------|
| Nov 2023 | HyperPod GA (Slurm only) |
| Sep 2024 | EKS orchestrator + Terraform/CloudFormation support |
| Nov 2024 | Multi-AZ support |
| Feb 2025 | Per-instance-group VPC config |
| Jul 2025 | Amazon Linux 2023 for EKS, unified observability |
| Sep 2025 | Health monitoring agent for Slurm |

**Sources (Tier 1)**: SageMaker HyperPod docs, CreateCluster API reference, AWSCC Terraform Registry

---

## 4. GitOps + Terraform Patterns

### Atlantis (v0.40.0) — Recommended for Terraform GitOps

- Self-hosted, PR-based workflow: PR opens → auto `terraform plan` → comment → `atlantis apply`
- `atlantis.yaml` v3: project configs, `when_modified` globs, `depends_on`, `execution_order_group`
- Supports: GitHub, GitLab, Bitbucket, Azure DevOps
- GitHub App recommended for authentication

### HCP Terraform (Terraform Cloud)

- VCS-driven: speculative plans on PRs, auto-apply on merge
- Policy-as-code: Sentinel + OPA (both GA)
- **Free tier EOL: March 31, 2026**

### Alternatives

| Platform | Differentiator |
|----------|---------------|
| Spacelift | Multi-IaC (TF, Terragrunt, Pulumi, K8s), drift detection, stack dependencies |
| env0 | FinOps focus, cost estimation, budget guardrails |
| Scalr | Three-tier hierarchy (Account→Environment→Workspace), granular RBAC |

### Crossplane (v2.2, CNCF graduated Nov 2025)

- K8s-native alternative: AWS resources as CRDs, ArgoCD syncs from Git
- `provider-upjet-aws` covers hundreds of AWS resource types
- True continuous reconciliation (drift auto-corrected)
- Best for teams wanting K8s-native infrastructure GitOps

### Drift Detection

- Scheduled `terraform plan -detailed-exitcode` in CI (exit code 2 = drift)
- Platform-native: Spacelift, env0, HCP Terraform Health Assessments
- `terraform plan -refresh-only -detailed-exitcode` for refresh-only drift checks

### State Management

- **S3 with native S3 locking** (Terraform v1.10+, `use_lockfile = true`)
- DynamoDB-based locking is **deprecated**
- State key pattern: `{env}/{component}/terraform.tfstate`
- Always enable: bucket versioning, encryption, public access block

### Module Composition

- Dependency inversion: modules accept dependencies as inputs, root module wires them
- Flat hierarchy: one level of child modules
- Semantic versioning with Git tags
- Pin versions in production, `~>` constraint for controlled upgrades

### Environment Promotion

- **Directory-based** (recommended): Clear separation, independent state
- **Workspace-based**: Good when architecture identical across envs
- **Branch-based**: NOT recommended (drift, merge conflicts)
- GitOps flow: PR → plan against dev → merge → apply dev → promote to staging → promote to prod

### Policy as Code

| Tool | Status | Language |
|------|--------|----------|
| OPA v1.14.0 | Active, CNCF graduated | Rego |
| Sentinel | Active (HashiCorp only) | Sentinel |
| Checkov v3.2.506 | Active | Python |
| tfsec | Deprecated → Trivy | Go |

### CI/CD

- GitHub Actions: `hashicorp/setup-terraform@v2` + OIDC for AWS auth (no long-lived credentials)
- Pattern: PR → plan → merge → apply with environment approval gates

**Sources (Tier 1)**: Atlantis docs, HashiCorp Terraform docs, Crossplane docs

---

## 5. Shared Infrastructure

### VPC and Networking

- Single VPC can host all three cluster types
- Module: `terraform-aws-modules/vpc/aws` v5.x/v6.x
- Private subnets (/16+) for compute, public subnets (/24) for NAT
- HyperPod EKS uses 3-VPC architecture (2 AWS-managed + 1 user-managed)

### EFA Requirements (critical for all GPU clusters)

- Cluster placement group (same AZ)
- Security group: ALL traffic self-referencing (`protocol -1, source-group = self`)
- VPC CNI v1.18.4+ for EKS EFA
- terraform-aws-eks: `enable_efa_support = true` auto-configures everything

### Storage

**FSx for Lustre** (`aws_fsx_lustre_file_system`):
- PERSISTENT_2 recommended for ML (flexible throughput: 125/250/500/1000 MB/s/TiB)
- S3 DRA via separate `aws_fsx_data_repository_association` (required for PERSISTENT_2)
- Module: `terraform-aws-modules/fsx/aws`

**EFS** (`aws_efs_file_system`):
- Elastic throughput mode recommended
- Access points for multi-tenant isolation
- Module: `terraform-aws-modules/efs/aws`

**Cross-cluster mounting:**

| Storage | ParallelCluster | EKS | HyperPod |
|---------|----------------|-----|----------|
| FSx Lustre | SharedStorage YAML | FSx CSI Driver + PV/PVC | FsxLustreConfig in instance group |
| EFS | SharedStorage YAML | EFS CSI Driver + PV/PVC | EFS CSI via EKS add-ons |
| S3 | IAM roles | Mountpoint for S3 CSI / IRSA | IAM roles |

### IAM

- **ParallelCluster**: Head node role (EC2, DynamoDB, S3, CFN), compute node role (minimal)
- **EKS**: Pod Identity (default in v21.x), node IAM role
- **HyperPod**: `AmazonSageMakerClusterInstanceRolePolicy`, execution role per instance group
- **Cross-cluster**: Shared KMS key, resource-based S3 policies, tag-based IAM scoping

### Monitoring

- **ParallelCluster**: Auto CloudWatch dashboard, Slurm exporter + Prometheus + Grafana (aws-samples/aws-parallelcluster-monitoring)
- **EKS**: DCGM Exporter → Prometheus → Grafana (or AMP + AMG), CloudWatch Container Insights
- **HyperPod**: Deep health checks, Health Monitoring Agent, CloudWatch logs, unified observability (Jul 2025)

### Security

- EFA SG: self-referencing all-traffic rules
- Shared KMS key across all cluster types
- Secrets Manager for credentials, SSM Parameter Store for config
- EKS: Network policies via Calico or VPC CNI Network Policy Controller
- ECR: `image_tag_mutability = "IMMUTABLE"` for ML reproducibility

**Sources (Tier 1)**: AWS VPC docs, FSx docs, EKS best practices, Well-Architected ML Lens

---

## 6. Multi-Cluster Terraform Patterns

### Recommended Structure: Monorepo + Multi-Account + Terragrunt

```
ml-clusters/
  modules/                                    # Reusable Terraform modules
    networking/                               # VPC, subnets, security groups
    shared-storage/                           # FSx Lustre, EFS
    s3-data-bucket/                           # Central + replica S3 buckets
    s3-replication/                           # Cross-region/cross-account replication
    iam/                                      # IAM roles and policies
    eks-cluster/                              # Wraps terraform-aws-eks
    parallelcluster/                          # Wraps aws-tf/parallelcluster
    hyperpod/                                 # Wraps awscc_sagemaker_cluster
    monitoring/                               # CloudWatch, Prometheus
  live/
    terragrunt.hcl                            # Root: remote_state, generate provider
    _envcommon/                               # Shared component configs
      networking.hcl
      eks-cluster.hcl
      parallelcluster.hcl
    main-account/                             # Account 483026362307
      account.hcl                             # account_id, account_name, is_management
      us-east-1/
        region.hcl                            # aws_region, AZs
        networking/terragrunt.hcl
        iam/terragrunt.hcl
        s3-central-data/terragrunt.hcl        # Central data bucket
        s3-tfstate/terragrunt.hcl             # Terraform state bucket (bootstrap)
        s3-replication/terragrunt.hcl         # Replication rules to all regions/accounts
        shared-storage/terragrunt.hcl         # FSx Lustre, EFS
        eks-training/terragrunt.hcl
        parallelcluster/terragrunt.hcl
        monitoring/terragrunt.hcl
      us-west-2/
        region.hcl
        networking/terragrunt.hcl
        s3-data-replica/terragrunt.hcl        # Regional replica bucket
        shared-storage/terragrunt.hcl
        eks-inference/terragrunt.hcl
    secondary-account/                        # Account 159553542841
      account.hcl                             # account_id, account_name
      us-east-1/
        region.hcl
        networking/terragrunt.hcl
        iam/terragrunt.hcl
        s3-data-replica/terragrunt.hcl        # Cross-account replica bucket
      us-west-2/
        region.hcl
        networking/terragrunt.hcl
        s3-data-replica/terragrunt.hcl
        shared-storage/terragrunt.hcl
        eks-training/terragrunt.hcl
        hyperpod-slurm/terragrunt.hcl
  cluster-configs/                            # ParallelCluster YAML, HyperPod lifecycle scripts
    parallelcluster/
    hyperpod/lifecycle-scripts/
  gitops/                                     # ArgoCD app manifests for EKS clusters
    apps/
    add-ons/
  tests/
    unit/*.tftest.hcl
    integration/*.go
```

### Multi-Account Configuration

**account.hcl** (per account):
```hcl
# live/main-account/account.hcl
locals {
  account_id            = "483026362307"
  account_name          = "main"
  is_management_account = true
  state_bucket          = "ml-clusters-tfstate-483026362307"
  ecr_registry          = "483026362307.dkr.ecr.us-east-1.amazonaws.com"
}

# live/secondary-account/account.hcl
locals {
  account_id            = "159553542841"
  account_name          = "secondary"
  is_management_account = false
  state_bucket          = "ml-clusters-tfstate-483026362307"  # Central state
  ecr_registry          = "483026362307.dkr.ecr.us-east-1.amazonaws.com"  # Pull from main
}
```

**Root terragrunt.hcl** (auto-generates provider with `assume_role`):
```hcl
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  account_id   = local.account_vars.locals.account_id
  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
}

remote_state {
  backend = "s3"
  generate = { path = "backend.tf", if_exists = "overwrite_terragrunt" }
  config = {
    bucket       = "ml-clusters-tfstate-483026362307"
    key          = "${local.account_name}/${path_relative_to_include()}/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
  assume_role {
    role_arn = "arn:aws:iam::${local.account_id}:role/TerraformExecutionRole"
  }
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Account   = "${local.account_name}"
      Region    = "${local.aws_region}"
    }
  }
}
EOF
}
```

**State key pattern**: `{account_name}/{region}/{component}/terraform.tfstate`
- Example: `main/us-east-1/eks-training/terraform.tfstate`
- Example: `secondary/us-west-2/hyperpod-slurm/terraform.tfstate`

### Cross-Account IAM

- **Main account (483026362307)**: `TerraformCIRole` — used by CI/CD (GitHub Actions OIDC)
- **Secondary account (159553542841)**: `TerraformExecutionRole` — trusts main account's CI role via `sts:AssumeRole`
- Cross-account resources (S3 replication, ECR pull, KMS decrypt) use resource-based policies + IAM role permissions (both required)
- IAM role chaining has 1-hour max session; prefer direct OIDC federation for long-running operations

### S3 Data Distribution (Hub-and-Spoke)

**Architecture**:
```
Central bucket (483026362307, us-east-1)
    ├──→ CRR → Replica (483026362307, us-west-2)      # Same-account, cross-region
    ├──→ CRR → Replica (159553542841, us-east-1)      # Cross-account, same-region
    └──→ CRR → Replica (159553542841, us-west-2)      # Cross-account, cross-region
```

**Key requirements**:
- Source and all destination buckets must have versioning enabled
- IAM replication role assumed by `s3.amazonaws.com` service
- Cross-account: destination bucket policy must allow `s3:ReplicateObject`, `s3:ReplicateDelete` from source replication role
- Cross-account: `access_control_translation { owner = "Destination" }` to transfer object ownership
- KMS: source role needs `kms:Decrypt` on source key + `kms:Encrypt` on each destination key
- S3 Replication Time Control (RTC): guarantees 15-minute SLA with `replication_time` block
- Multiple replication rules with priority + prefix filters (e.g., `datasets/` → STANDARD_IA, `checkpoints/` → GLACIER_IR)

**Terraform resources**:
- `aws_s3_bucket` + `aws_s3_bucket_versioning` for each bucket
- `aws_s3_bucket_replication_configuration` on central bucket (one rule per destination)
- `aws_s3_bucket_policy` on cross-account destination buckets
- `aws_iam_role` + `aws_iam_role_policy` for S3 replication service
- Cross-account KMS key policies granting `kms:Encrypt` to source account

### Cross-Account Networking

- **VPC Peering** (for 2 accounts): `aws_vpc_peering_connection` + `aws_vpc_peering_connection_accepter` + route table entries
- **Transit Gateway** (scalable): Share via RAM (`aws_ram_resource_share`), attach VPCs from both accounts
- **Non-overlapping CIDRs required**: Plan VPC CIDRs per account/region upfront
- Cross-account EFS: mount by IP address (not DNS), EFS resource policy for cross-account access, AZ IDs (not names) for consistency
- Cross-account ECR: repository policy + node role IAM permissions + KMS decrypt for encrypted images

### Terragrunt (v0.99.4, approaching 1.0)

- `include` blocks for DRY parent config inheritance
- `dependency` blocks for cross-module output passing + DAG ordering
- `generate` blocks for provider/backend config injection
- `remote_state` auto-generates state keys from directory structure via `path_relative_to_include()`
- `terragrunt run --all apply` applies entire DAG in order
- `iam_role` directive for Terragrunt-level role assumption (alternative to provider `assume_role`)

### State Management

- Central S3 state bucket in main account (483026362307, us-east-1)
- Native S3 locking (`use_lockfile = true`, Terraform 1.10+) — no DynamoDB needed
- One state file per component per account per region
- Cross-state refs: `terraform_remote_state` or AWS data sources (preferred for loose coupling)
- Cross-account state access: S3 bucket policy grants access to `TerraformExecutionRole` in secondary account

### Dependency Graph (Multi-Account)

```
[main-account/us-east-1]
  networking ──→ iam ──→ eks-training ──→ argocd-bootstrap
       │          │  ──→ parallelcluster
       │          └──→ s3-replication (needs cross-account provider)
       ├──→ shared-storage (FSx, EFS)
       ├──→ s3-central-data
       └──→ monitoring

[main-account/us-west-2]
  networking ──→ eks-inference ──→ argocd-bootstrap
       ├──→ shared-storage
       └──→ s3-data-replica

[secondary-account/us-west-2]
  networking ──→ iam ──→ eks-training ──→ argocd-bootstrap
       │          └──→ hyperpod-slurm
       ├──→ shared-storage
       └──→ s3-data-replica

Cross-account dependencies:
  s3-replication (main) ──→ s3-data-replica (secondary, all regions)
  ECR (main) ←── EKS nodes (secondary) [pull images]
  KMS key (main) ←── all clusters (secondary) [decrypt shared data]
```

### Testing

- `terraform test` (v1.6+): Unit tests with `command = plan`, mocking (v1.7+)
- Terratest (Go): Complex integration tests with real infrastructure
- CI pipeline: fmt → validate → tflint → plan → test → policy check → manual approval → apply

### Module Versioning

- Git tags with semver (`?ref=v2.1.0`)
- Pin exact versions in production
- `~>` constraint for controlled minor/patch upgrades
- Private registry (HCP TF, Spacelift, Scalr) for larger teams

**Sources (Tier 1)**: HashiCorp docs, Terragrunt docs, AWS Prescriptive Guidance, AWS S3 Replication docs

---

## 7. GPU Capacity Reservation: EC2 Capacity Blocks & SageMaker Training Plans

### Overview

Two mechanisms exist for reserving P-series GPU instances:

| Feature | EC2 Capacity Blocks | SageMaker Training Plans |
|---------|---------------------|--------------------------|
| Scope | Raw EC2 instances | SageMaker-managed (training jobs, HyperPod, endpoints) |
| Instance prefix | `p5.48xlarge` | `ml.p5.48xlarge` |
| Duration | 1-182 days (see [AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html) for current limits) | 1-182 days (1-day increments) |
| Max instances | 64 per block, 256 total | 64 per plan, 256 total |
| Pricing | Upfront fixed fee, dynamic supply/demand | Upfront fixed fee, dynamic supply/demand |
| Advance booking | Up to 8 weeks | Up to 8 weeks (min 30 min) |
| Discounts | No Savings Plans / RI | No Savings Plans / RI |
| Extensions | Yes (unlimited) | No |
| Integration | EKS, ParallelCluster, raw EC2 | SageMaker Training Jobs, HyperPod, Endpoints |
| Terraform | `aws_ec2_capacity_block_reservation` | No Terraform resource (CLI/SDK only) |
| Auto-splitting | No | Yes (splits across 2 blocks if needed) |

### EC2 Capacity Blocks — Supported Instance Types

p4d.24xlarge, p4de.24xlarge, p5.4xlarge, p5.48xlarge, p5e.48xlarge, p5en.48xlarge, p6-b200.48xlarge, p6-b300.48xlarge, trn1.32xlarge, trn2.48xlarge

**Note**: Instance type availability changes over time. Check the [AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-blocks.html) for the current list. UltraServer Capacity Blocks (Trn2, P6e-GB200) have separate limits and behavior.

### SageMaker Training Plans — Supported Instance Types

ml.p4d.24xlarge, ml.p4de.24xlarge, ml.p5.48xlarge, ml.p5e.48xlarge, ml.p5en.48xlarge, ml.p6-b200.48xlarge, ml.p6-b300.48xlarge, ml.p6e-gb200.36xlarge, ml.trn1.32xlarge, ml.trn2.48xlarge

### CLI Workflows (for Claude Code Skills)

**EC2 Capacity Blocks — Search → Purchase → Monitor → Extend:**

```bash
# Search
aws ec2 describe-capacity-block-offerings \
  --capacity-duration-hours 168 \
  --instance-type p5.48xlarge \
  --instance-count 8 \
  --start-date-range "2026-03-01T00:00:00Z" \
  --end-date-range "2026-03-31T23:59:59Z"

# Purchase
aws ec2 purchase-capacity-block \
  --capacity-block-offering-id cbo-XXXXX \
  --instance-platform "Linux/UNIX" \
  --tag-specifications 'ResourceType=capacity-block,Tags=[{Key=Team,Value=ML}]'

# Monitor
aws ec2 describe-capacity-blocks --filters Name=state,Values=scheduled,active
aws ec2 describe-capacity-block-status --capacity-block-ids cb-XXXXX

# Extend
aws ec2 describe-capacity-block-extension-offerings \
  --capacity-block-extension-duration-hours 48 \
  --capacity-reservation-id cr-XXXXX
aws ec2 purchase-capacity-block-extension \
  --capacity-block-extension-offering-id cbeo-XXXXX \
  --capacity-reservation-id cr-XXXXX
```

**SageMaker Training Plans — Search → Purchase → Monitor:**

```bash
# Search (target-resources: training-job | hyperpod-cluster | endpoint)
aws sagemaker search-training-plan-offerings \
  --target-resources "hyperpod-cluster" \
  --instance-type "ml.p5.48xlarge" \
  --instance-count 8 \
  --duration-hours 48 \
  --start-time-after "$(date -d '+3 days' +%s)" \
  --end-time-before "$(date -d '+14 days' +%s)"

# Purchase
aws sagemaker create-training-plan \
  --training-plan-name "my-plan" \
  --training-plan-offering-id "tpo-XXXXX"

# Monitor
aws sagemaker list-training-plans --filters Name=Status,Value=Active
aws sagemaker describe-training-plan --training-plan-name "my-plan"
```

### Integration with Cluster Types

**EKS (Karpenter) + Capacity Blocks:**
```yaml
# EC2NodeClass
spec:
  capacityReservationSelectorTerms:
    - id: "cr-XXXXX"
# NodePool
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["reserved"]
```

**ParallelCluster + Capacity Blocks (v3.8+):**
```yaml
SlurmQueues:
  - Name: gpu-queue
    CapacityType: CAPACITY_BLOCK
    ComputeResources:
      - Name: p5-nodes
        InstanceType: p5.48xlarge
        MinCount: 8    # Must equal MaxCount (static nodes)
        MaxCount: 8
        CapacityReservationTarget:
          CapacityReservationId: cr-XXXXX
```

**HyperPod + Training Plans:**
```json
{
  "InstanceGroupName": "gpu-workers",
  "InstanceType": "ml.p5.48xlarge",
  "InstanceCount": 8,
  "TrainingPlanArn": "arn:aws:sagemaker:us-east-1:ACCOUNT:training-plan/my-plan"
}
```

### Terraform Support

| Mechanism | Terraform Resource | Status |
|-----------|-------------------|--------|
| EC2 Capacity Block (search) | `data.aws_ec2_capacity_block_offering` | Available |
| EC2 Capacity Block (purchase) | `aws_ec2_capacity_block_reservation` | Available |
| SageMaker Training Plan | None | Not available — CLI/SDK only |

### Claude Code Skill Design

Two skills needed:

**Skill: `capacity-blocks`** — Search and purchase EC2 Capacity Blocks
- Search with filters: instance type, count, duration, date range, region
- Display offerings in table format (AZ, dates, price)
- Purchase with confirmation prompt (upfront cost)
- List active/scheduled blocks with utilization
- Search and purchase extensions

**Skill: `training-plans`** — Search and purchase SageMaker Training Plans
- Search with filters: target resource, instance type, count, duration, date range
- Display offerings (may return split blocks across 2 time windows)
- Purchase with confirmation prompt
- List active plans with utilization (available/in-use/unhealthy counts)
- Show AZ information (critical for HyperPod subnet selection)

**Sources (Tier 1)**: EC2 Capacity Blocks docs, SageMaker Training Plans docs, AWS CLI reference, Terraform Registry

---

## Provider Summary

| Cluster Type | Terraform Provider | Resource |
|-------------|-------------------|----------|
| ParallelCluster | `aws-tf/aws-parallelcluster` | `aws-parallelcluster_cluster` |
| EKS | `hashicorp/aws` | `aws_eks_cluster` (via terraform-aws-eks module) |
| HyperPod | `hashicorp/awscc` | `awscc_sagemaker_cluster` |
| Shared Infra | `hashicorp/aws` | VPC, FSx, EFS, IAM, SGs, etc. |

## Version Summary

| Component | Version |
|-----------|---------|
| Terraform CLI | 1.14.x |
| Terragrunt | 0.99.4 |
| terraform-aws-eks | v21.15.1 |
| terraform-aws-eks-blueprints-addons | v1.23.0 |
| aws-tf/aws-parallelcluster provider | v1.1.0 |
| aws-tf/parallelcluster module | v1.1.0 |
| hashicorp/awscc provider | >= v1.23.0 |
| Karpenter | v1.8.6 |
| ArgoCD | v2.x |
| Flux | v1.8.1 (TF provider) |
| Atlantis | v0.40.0 |
| Crossplane | v2.2 |
| Checkov | v3.2.506 |
| OPA | v1.14.0 |
| NVIDIA device plugin | v0.17.1 |
| ParallelCluster | 3.14.2 (latest) |

---

## Gaps and Open Questions

1. **HyperPod Terraform module**: No official module exists. Need to build a custom module wrapping `awscc_sagemaker_cluster` + supporting infra.
2. **ParallelCluster API deployment**: The API must be deployed via CloudFormation before Terraform can manage clusters. This creates a chicken-and-egg dependency.
3. **HyperPod + EKS orchestrator with Terraform**: Creating the EKS cluster (hashicorp/aws) then referencing it in HyperPod (hashicorp/awscc) requires coordinating two providers.
4. **Lifecycle script management**: HyperPod lifecycle scripts in S3 need a deployment mechanism (CI/CD or Terraform `aws_s3_object`).
5. **Cross-cluster Slurm federation**: Not researched — may be needed if ParallelCluster and HyperPod Slurm clusters need to share jobs.
6. **Capacity reservations**: Capacity Blocks integrate with EKS (Karpenter `capacityReservationSelectorTerms`), ParallelCluster (`CapacityType: CAPACITY_BLOCK`), and HyperPod (`TrainingPlanArn`). Note: enabling `capacityReservationSelectorTerms` on ANY NodeClass disables automatic ODCR usage for ALL NodeClasses in the EKS cluster.
7. **Cost management**: No deep research on cost optimization patterns across cluster types.
8. **VPC CIDR planning**: Need non-overlapping CIDRs across 2 accounts × multiple regions. Plan upfront (e.g., 10.0.0.0/16 main-use1, 10.1.0.0/16 main-usw2, 10.2.0.0/16 secondary-use1, 10.3.0.0/16 secondary-usw2).
9. **S3 replication lag**: Checkpoint/model data may have time-sensitive replication requirements. RTC guarantees 15 minutes but not instant.
10. **Cross-account FSx Lustre**: FSx Lustre does NOT support cross-account mounting directly. Each account/region needs its own FSx filesystem populated from the local S3 replica via DRA.
11. **SageMaker Training Plans Terraform gap**: No Terraform resource exists for Training Plans. Must use CLI/SDK, which means the Claude Code skill is the primary management interface.
12. **Capacity Block AZ constraint**: Both Capacity Blocks and Training Plans are AZ-specific. Cluster subnets must match the AZ of the purchased capacity.

---

## Sources Consulted

### Primary (Tier 1)
- AWS ParallelCluster documentation (docs.aws.amazon.com/parallelcluster/)
- Amazon EKS documentation (docs.aws.amazon.com/eks/)
- SageMaker HyperPod documentation (docs.aws.amazon.com/sagemaker/)
- Terraform AWS provider documentation (registry.terraform.io)
- terraform-aws-eks GitHub (github.com/terraform-aws-modules/terraform-aws-eks)
- aws-tf/terraform-provider-aws-parallelcluster GitHub
- Karpenter documentation (karpenter.sh/docs/)
- ArgoCD documentation (argo-cd.readthedocs.io)
- HashiCorp Terraform documentation (developer.hashicorp.com/terraform/)
- Terragrunt documentation (terragrunt.gruntwork.io)
- Atlantis documentation (runatlantis.io/docs/)
- Crossplane documentation (docs.crossplane.io)

### Secondary (Tier 2)
- AWS blog posts (aws.amazon.com/blogs/)
- EKS Blueprints patterns (aws-ia.github.io/terraform-aws-eks-blueprints/)
- AWS Prescriptive Guidance (docs.aws.amazon.com/prescriptive-guidance/)
- gitops-bridge-dev/gitops-bridge GitHub
- aws-samples/awsome-distributed-training GitHub
- Spacelift, env0, Scalr documentation and blogs
- HashiCorp Tutorial: Provision AWS resources across accounts using AssumeRole
- Terragrunt multi-account documentation (terragrunt.gruntwork.io/docs/features/aws-auth/)
- gruntwork-io/terragrunt-infrastructure-live-example GitHub
- AWS S3 Replication docs (docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- AWS Storage Blog: Cross-account EFS with EKS
- AWS KMS docs: cross-account key access
