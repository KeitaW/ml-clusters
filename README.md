# ml-clusters

Unified, multi-account, multi-region infrastructure management for AWS ML workloads. Provisions and manages shared infrastructure across **EKS**, **ParallelCluster**, and **SageMaker HyperPod** using Terraform + Terragrunt, with PR-based GitOps via Atlantis and Kubernetes workload management via ArgoCD.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Git Repository                          │
│  Terraform Modules │ Terragrunt Live │ GitOps Manifests     │
└────────┬────────────────────┬───────────────────┬───────────┘
         │                    │                   │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │Atlantis │         │Terraform│         │ ArgoCD  │
    │(PR Plan/│────────▶│ Apply   │         │(K8s App │
    │ Apply)  │         │         │         │  Sync)  │
    └─────────┘         └────┬────┘         └────┬────┘
                             │                   │
         ┌───────────────────┼───────────────────┼──────────┐
         │              AWS Accounts              │          │
         │                                                   │
         │  ┌─────────────────────────────────────────────┐  │
         │  │ Main Account (us-east-1)                    │  │
         │  │  VPC ─ EKS ─ ParallelCluster ─ Monitoring  │  │
         │  │  FSx Lustre ─ EFS ─ S3 ─ KMS ─ Cognito     │  │
         │  └─────────────────────────────────────────────┘  │
         │  ┌─────────────────────────────────────────────┐  │
         │  │ Main Account (us-west-2)                    │  │
         │  │  VPC ─ EKS Inference ─ S3 Replica ─ Storage │  │
         │  └─────────────────────────────────────────────┘  │
         │  ┌─────────────────────────────────────────────┐  │
         │  │ Secondary Account (us-west-2)               │  │
         │  │  VPC ─ EKS ─ HyperPod ─ S3 Replica         │  │
         │  └─────────────────────────────────────────────┘  │
         └───────────────────────────────────────────────────┘
```

### Key design decisions

- **Shared infrastructure**: VPC, FSx Lustre, EFS, IAM, and KMS are shared across all cluster types (EKS, ParallelCluster, HyperPod)
- **PR-based workflow**: All infrastructure changes go through Atlantis with automated `terraform plan` on PRs
- **GitOps for K8s**: ArgoCD manages Kubernetes add-ons and workloads via app-of-apps pattern
- **Cross-account data**: Central S3 bucket with cross-region replication and KMS cross-account access
- **GPU procurement**: Claude Code skills for EC2 Capacity Blocks and SageMaker Training Plans

## Repository structure

```
ml-clusters/
├── modules/                  # Terraform modules (12)
│   ├── networking/           #   VPC, subnets, NAT, EFA SG, placement groups, VPC endpoints
│   ├── iam/                  #   KMS, TerraformExecutionRole, cross-account access
│   ├── s3-data-bucket/       #   Central ML data bucket with versioning + encryption
│   ├── s3-replication/       #   Cross-region/account S3 replication
│   ├── shared-storage/       #   FSx Lustre (PERSISTENT_2) + EFS (elastic)
│   ├── eks-cluster/          #   EKS with managed addons, Karpenter, IRSA
│   ├── argocd/               #   ArgoCD helm + ApplicationSet bootstrap
│   ├── atlantis/             #   Atlantis helm + dual ingress (webhook/UI)
│   ├── midway-auth/          #   Cognito + OIDC federation + Route53 + ACM
│   ├── parallelcluster/      #   ParallelCluster API + Slurm cluster
│   ├── monitoring/           #   AMP + Alertmanager + SNS + Prometheus rules
│   └── hyperpod/             #   SageMaker HyperPod (Slurm/EKS orchestrator)
├── live/                     # Terragrunt environment configs
│   ├── terragrunt.hcl        #   Root config (S3 backend, provider generation)
│   ├── _envcommon/           #   Shared module references
│   ├── main-account/         #   Account 483026362307
│   │   ├── us-east-1/        #     Primary region (fully deployed)
│   │   └── us-west-2/        #     Secondary region (scaffolded)
│   └── secondary-account/    #   Account 159553542841
│       └── us-west-2/        #     (scaffolded)
├── gitops/                   # Kubernetes manifests (ArgoCD-managed)
│   ├── add-ons/              #   AWS LB Controller, External-DNS, Karpenter,
│   │                         #   NVIDIA device plugin, ADOT, DCGM exporter
│   ├── karpenter-config/     #   NodePool + EC2NodeClass
│   └── workloads/            #   User workloads
├── cluster-configs/          # Non-K8s cluster configs
│   ├── parallelcluster/      #   Slurm cluster YAML
│   └── hyperpod/             #   HyperPod lifecycle scripts
├── skills/                   # Claude Code skills
│   ├── capacity-blocks/      #   /capacity-blocks (search/buy/list EC2 GPU blocks)
│   └── training-plans/       #   /training-plans (search/buy/list SageMaker plans)
├── tests/                    # Integration tests (Terratest)
├── docs/                     # Design doc, runbooks
│   └── design.md             #   Full architecture design document
├── atlantis.yaml             # Atlantis project/workflow config
├── .terraform-version        # 1.14.5
└── .terragrunt-version       # 0.99.4
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.14.5
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.99.4
- AWS CLI configured with credentials for the target accounts
- IAM `TerraformExecutionRole` in each account

## Quick start

```bash
# Clone the repo
git clone https://github.com/KeitaW/ml-clusters.git
cd ml-clusters/ml-clusters

# Deploy networking in main-account/us-east-1
cd live/main-account/us-east-1/networking
terragrunt plan
terragrunt apply

# Deploy all resources in dependency order
cd live/main-account/us-east-1
terragrunt run-all plan
terragrunt run-all apply
```

## Deployment order

Infrastructure must be deployed in dependency order. Atlantis enforces this via execution groups defined in `atlantis.yaml`:

| Group | Components | Purpose |
|-------|-----------|---------|
| 0 | IAM, Networking | Foundation: roles, KMS, VPC, subnets |
| 1 | S3 buckets | Central data storage, tfstate |
| 2 | S3 replication, Shared storage | FSx Lustre, EFS, cross-region sync |
| 3 | EKS clusters | Training + inference compute |
| 4 | ParallelCluster, HyperPod, Midway auth | Slurm clusters, authentication |
| 5 | ArgoCD, Atlantis, Monitoring | GitOps, CI/CD, observability |

## Making changes

All infrastructure changes follow the Atlantis PR workflow:

1. Create a feature branch and make changes
2. Open a PR — Atlantis automatically runs `terragrunt plan`
3. Review the plan output in the PR comments
4. Comment `atlantis apply` to apply after approval
5. Merge the PR

## Cluster types

| Cluster | Orchestrator | Best for | Module |
|---------|-------------|----------|--------|
| **EKS** | Kubernetes | K8s-native teams, inference, containerized training | `eks-cluster` |
| **ParallelCluster** | Slurm | Traditional HPC, Slurm-native teams | `parallelcluster` |
| **HyperPod (Slurm)** | Slurm | Large-scale fault-tolerant training | `hyperpod` |
| **HyperPod (EKS)** | Kubernetes | K8s teams wanting HyperPod resiliency | `hyperpod` |

## Observability

- **Amazon Managed Prometheus (AMP)**: Metrics storage via ADOT collector
- **ADOT Collector**: Scrapes pod metrics + cAdvisor, remote-writes to AMP
- **DCGM Exporter**: GPU metrics (utilization, memory, temperature) via DaemonSet
- **Alertmanager**: Routes alerts to SNS (CPU, memory, storage, IP exhaustion)

## Testing

```bash
# Unit tests (Terraform native, mock providers)
cd modules/networking
terraform test

# Integration tests (Terratest, real AWS resources)
cd tests/integration
go test -v -timeout 60m ./...
```

## Documentation

- [Design document](docs/design.md) — full architecture design, phased rollout, and decision rationale
- [Midway auth runbook](docs/runbooks/midway-auth-setup.md) — Cognito + OIDC setup guide

## Tooling versions

| Tool | Version |
|------|---------|
| Terraform | 1.14.5 |
| Terragrunt | 0.99.4 |
| AWS Provider | ~> 6.34 |
| EKS Module | ~> 21.15 |
| ParallelCluster | 3.12.0 |
