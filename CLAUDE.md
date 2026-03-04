# CLAUDE.md

## Overview

Multi-account, multi-region ML infrastructure. Terraform + Terragrunt for provisioning,
Atlantis for PR-based plan/apply, ArgoCD for Kubernetes workloads.

See `docs/design.md` for architecture decisions.

## Accounts

| Account | ID | Purpose |
|---------|-----|---------|
| Main | 483026362307 | Atlantis, ArgoCD, EKS, ParallelCluster, Monitoring |
| Secondary | 159553542841 | EKS training, HyperPod |

Both have `TerraformExecutionRole` (AdministratorAccess). Root terragrunt generates
`assume_role` targeting this role per account.

## Tooling

- Terraform 1.14.5 / Terragrunt 0.99.4 / AWS Provider ~> 6.34
- State: `ml-clusters-tfstate-483026362307` (us-east-1), S3-native locking
- `.terraform-version` and `.terragrunt-version` pin versions at repo root

## Repository Layout

- `modules/` — Terraform modules (self-contained, no provider generation)
- `live/{account}/{region}/{component}/terragrunt.hcl` — Environment configs
- `live/terragrunt.hcl` — Root config (S3 backend, provider generation with assume_role)
- `atlantis.yaml` — Project list + terragrunt workflow (execution groups 0–5)
- `gitops/` — ArgoCD-managed K8s manifests (add-ons, karpenter-config, workloads)
- `cluster-configs/` — Non-K8s cluster configs (ParallelCluster YAML, HyperPod scripts)

## Key Constraints

### Terraform / Terragrunt
- Root terragrunt generates `provider.tf` (with assume_role) and `backend.tf` — modules
  must NOT define their own provider or backend blocks
- Each module has its own `versions.tf` with required_providers
- S3 backend has NO assume_role — callers need direct S3 bucket access
- IAM roles are account-wide: always include cluster name suffix for uniqueness
  (e.g., `ALBController-${var.cluster_name}`)
- KMS keys are regional — each region needs its own key
- `mock_provider` in terraform tests still enforces plan-time validators — use `mock_data`
  for policy documents and VPC CIDRs

### Atlantis
- Workflow uses `/extra-bin/terragrunt` (installed via init container)
- Pod Identity provides AWS credentials (not IRSA)
- `atlantis.yaml` execution groups enforce dependency ordering across projects
- Changes to modules/ or live/ trigger autoplan for matching projects

### ArgoCD
- App-of-apps pattern via ApplicationSet in `gitops/`
- CRD-dependent resources (EC2NodeClass, NodePool) must be in a separate Application
  from the chart that installs the CRDs
- OCI Helm charts (e.g., Karpenter from ECR) need explicit repo Secret with `enableOCI: "true"`

### Bootstrap (manual, not Terraform-managed)
- S3 state bucket and TerraformExecutionRole are created manually before Terragrunt can
  manage anything
- ParallelCluster API CloudFormation stack must exist before the provider can init
- Set `create_terraform_execution_role = false` in IAM module to avoid conflict

## Commands

```bash
# Plan a single component
cd live/main-account/us-east-1/networking && terragrunt plan

# Plan all in a region (dependency order)
cd live/main-account/us-east-1 && terragrunt run-all plan

# Run module unit tests
cd modules/networking && terraform test

# Set GitHub token for Atlantis deploys
export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"
```

## Change Workflow

All infrastructure changes go through Atlantis PRs:
1. Create feature branch, make changes
2. Open PR — Atlantis auto-runs `terragrunt plan`
3. Review plan in PR comments
4. `atlantis apply` to apply
5. Merge
