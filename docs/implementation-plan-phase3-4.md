# Implementation Plan: ParallelCluster, Monitoring, Claude Code Skills

**Author**: ML Infrastructure Team
**Date**: 2026-03-03
**Status**: Draft
**Parent**: [docs/design.md](design.md) — Phases 3 & 4

---

## 1. Summary

Three work items from the design doc rollout plan:

| Item | Phase | Code Status | Deployment Status | Effort |
|------|-------|-------------|-------------------|--------|
| ParallelCluster | 3 | Module scaffolded, cluster config ready | NOT DEPLOYED | Medium — requires IAM permission expansion + two-phase deploy |
| Monitoring stack | 4 | Module complete (AMP, AMG, alerting) | NOT DEPLOYED | Small — straightforward apply, then wire ADOT to AMP |
| Claude Code skills | 4 | SKILL.md files written | FUNCTIONAL — need testing | Small — validate CLI commands, register skills |

**Dependency graph:**
```
  ┌──────────────────────┐  ┌────────────────────┐  ┌──────────────────────┐
  │  ParallelCluster      │  │  Monitoring stack   │  │  Claude Code skills   │
  │  (fix config + apply) │  │  (AMP + AMG)        │  │  (test + register)    │
  └──────────────────────┘  └────────────────────┘  └──────────────────────┘
      (provider fix only)        (independent)            (independent)
```

All three items are independent. TerraformExecutionRole already has `AdministratorAccess`, so no IAM expansion is needed for ParallelCluster (Codex review finding #2).

---

## 2. Item 1: ParallelCluster Deployment

### 2.1 Gap Analysis

**What exists:**
- `modules/parallelcluster/main.tf` — wraps `aws-tf/parallelcluster/aws ~> 1.1`, uses `templatefile()` for cluster YAML
- `modules/parallelcluster/variables.tf` — `cluster_configs` map with template variables
- `modules/parallelcluster/outputs.tf` — exposes `pcluster_api_stack_name` and `clusters`
- `cluster-configs/parallelcluster/training-cluster.yaml` — full Slurm config with two queues (gpu-ondemand, gpu-capacity-block), FSx + EFS mounts, EFA + GPU health checks
- `live/main-account/us-east-1/parallelcluster/terragrunt.hcl` — wired to networking/iam/shared-storage dependencies
- `live/_envcommon/parallelcluster.hcl` — passes region to module

**What needs fixing:**

#### Fix 1: Provider endpoint configuration (CRITICAL)
The terragrunt.hcl hardcodes a static endpoint URL (`https://pcluster-api.us-east-1.amazonaws.com`) which doesn't exist. The ParallelCluster API is an API Gateway deployed via CloudFormation into the customer's account. The provider should use `api_stack_name` for auto-discovery instead.

```hcl
# BEFORE (broken):
provider "aws-parallelcluster" {
  region   = "us-east-1"
  endpoint = "https://pcluster-api.us-east-1.amazonaws.com"  # ← doesn't exist
}

# AFTER (correct):
provider "aws-parallelcluster" {
  region         = "us-east-1"
  api_stack_name = "pcluster-api-us-east-1"
  use_user_role  = true
}
```

#### ~~Fix 2: IAM permissions~~ — NOT NEEDED
`TerraformExecutionRole` already has `AdministratorAccess` (modules/iam/main.tf:94-98), so no IAM expansion is required. The role can create CloudFormation stacks, Lambda functions, and API Gateway resources without any changes. *(Codex review finding #2 — removed from critical path.)*

#### Fix 3: Capacity Block queue should be optional
The `gpu-capacity-block` queue requires a `capacity_reservation_id` which won't exist on first deploy. The cluster config template uses `${capacity_reservation_id}` which will be empty string. ParallelCluster will fail if `CapacityReservationId` is present but empty.

**Fix:** Make the capacity-block queue conditional in the template, or remove it from the initial config and add it later when a reservation exists.

#### ~~Fix 4: Module versions.tf~~ — ALREADY EXISTS
The parallelcluster module already has `versions.tf` pinning `aws-parallelcluster ~> 1.1`. No action needed. *(Codex review finding #1 — removed.)*

#### Note: Capacity Block AZ must match reservation AZ
The compute subnet is in a single AZ (correct for EFA locality). When purchasing a Capacity Block reservation, the AZ must match the subnet AZ. Document this constraint for operators using the `/capacity-blocks` skill. *(Codex review finding #4.)*

### 2.2 Deployment Sequence

```
Step 1: Fix provider config + cluster config
  └→ Update terragrunt.hcl provider block (api_stack_name instead of endpoint)
  └→ Remove or conditionally gate the capacity-block queue
  └→ Commit + push

Step 2: terragrunt apply (first run deploys API stack + creates cluster)
  └→ deploy_pcluster_api=true triggers CloudFormation stack creation
  └→ CloudFormation stack deploys API Gateway + Lambda (takes ~5-10 min)
  └→ Module then creates the ParallelCluster cluster resource
  └→ Cluster creation takes ~15-25 min (head node + Slurm config)

Step 3: Validate
  └→ pcluster list-clusters --region us-east-1
  └→ SSH to head node via SSM (SSMManagedInstanceCore policy attached)
  └→ sinfo (verify Slurm queues)
  └→ df -h /fsx /home (verify shared storage mounts)
```

> **Note:** IAM verification step removed — TerraformExecutionRole has AdministratorAccess.

### 2.3 Files to Change

| File | Change |
|------|--------|
| `live/main-account/us-east-1/parallelcluster/terragrunt.hcl` | Fix provider block: use `api_stack_name` + `use_user_role`, remove hardcoded `endpoint`. Remove `capacity_reservation_id` from initial inputs (or set to empty and fix template). |
| `cluster-configs/parallelcluster/training-cluster.yaml` | Remove or condition-gate the `gpu-capacity-block` queue. Add conditional block around `CapacityReservationTarget`. |
| `modules/parallelcluster/main.tf` | Make `capacity_reservation_id` templatefile variable optional. |

---

## 3. Item 2: Monitoring Stack Deployment

### 3.1 Gap Analysis

**What exists:**
- `modules/monitoring/main.tf` — AMP workspace, AMG workspace with AWS SSO auth, Grafana IAM role with AMP+CloudWatch read permissions, Prometheus alerting rules (GPUIdle, EFAStalled, FSxIOPSHigh), CloudWatch alarms (subnet IP exhaustion, S3 replication lag)
- `modules/monitoring/variables.tf` — account_name, aws_region, vpc_id, private_subnet_ids, eks_cluster_name, alarm_sns_topic_arn
- `modules/monitoring/outputs.tf` — AMP workspace ID/endpoint, Grafana workspace ID/endpoint
- `live/main-account/us-east-1/monitoring/terragrunt.hcl` — wired to networking + EKS dependencies

**What needs fixing:**

#### Fix 1: AMG requires AWS IAM Identity Center (SSO) — BLOCKER
The Grafana workspace uses `authentication_providers = ["AWS_SSO"]`. AWS IAM Identity Center must be enabled in the account AND organization for this to work. If the account isn't part of an AWS Organization with Identity Center enabled, this will fail.

**Alternative:** Switch to `SAML` authentication (using Cognito as the SAML IdP, which is already deployed), or use API keys for initial access.

**Check first:** Run `aws sso-admin list-instances --region us-east-1` to verify Identity Center is configured.

#### Fix 2: No ADOT/Prometheus scraping pipeline
The AMP workspace exists but nothing pushes metrics into it. The EKS cluster needs:
1. **ADOT (AWS Distro for OpenTelemetry) Collector** — deployed as a DaemonSet in EKS, scrapes Prometheus endpoints and remote-writes to AMP
2. **DCGM Exporter** — DaemonSet on GPU nodes exposing NVIDIA GPU metrics (installed via ArgoCD)
3. **Node Exporter** — DaemonSet for system metrics
4. **IRSA role for ADOT** — with `aps:RemoteWrite` permission to push to AMP

Without this pipeline, the Prometheus alerting rules (GPUIdle, EFAStalled) will never fire because no metrics exist.

**Recommendation:** Deploy ADOT and DCGM as ArgoCD Applications in `gitops/add-ons/`. This keeps them consistent with the existing pattern (aws-lb-controller, external-dns, karpenter).

#### Fix 3: No SNS topic for alarm delivery
`alarm_sns_topic_arn` defaults to empty string, meaning alarms fire but no notifications are sent. Either create an SNS topic in the monitoring module or accept silent alarms initially.

#### Fix 4: No Alertmanager definition for AMP *(Codex finding #5)*
The `aws_prometheus_rule_group_namespace` defines alerting rules, but there is no `aws_prometheus_alert_manager_definition` resource. Without it, rules evaluate but alerts never route to any destination (SNS, PagerDuty, Slack). Add an Alertmanager config pointing to SNS for initial delivery.

#### Fix 5: S3 replication alarm missing dimensions *(Codex finding #6)*
The `s3_replication_lag` alarm has no `dimensions` block — the metric `AWS/S3 ReplicationLatency` requires `BucketName`, `DestinationBucket`, and `RuleId` dimensions to match any time series. Without them, the alarm will never fire. Fix: add dimensions with the actual bucket and replication rule, or defer this alarm until S3 replication is configured.

#### Fix 6: AMG `permission_type` + `role_arn` may conflict *(Codex finding #7)*
`permission_type = "SERVICE_MANAGED"` combined with an explicit `role_arn` may be rejected or the `role_arn` may be ignored. If Identity Center is available, use `SERVICE_MANAGED` without `role_arn`. If using SAML/API auth instead, switch to `CUSTOMER_MANAGED` with the explicit role.

### 3.2 Deployment Sequence

```
Step 1: Check IAM Identity Center
  └→ aws sso-admin list-instances --region us-east-1
  └→ If not enabled: switch AMG auth to SAML or skip AMG initially (deploy AMP only)

Step 2: terragrunt apply on monitoring
  └→ Creates: AMP workspace, AMG workspace (if SSO available), Grafana IAM role,
     alerting rules, CloudWatch alarms
  └→ Takes ~3-5 min

Step 3: Wire ADOT to AMP (post-Terraform)
  └→ Create IRSA role for ADOT with aps:RemoteWrite permission
  └→ Add ADOT Collector ArgoCD Application to gitops/add-ons/
  └→ Add DCGM Exporter ArgoCD Application to gitops/add-ons/
  └→ Commit + push → ArgoCD auto-syncs
  └→ Verify metrics flowing: aws amp get-series --workspace-id <id>

Step 4: Configure Grafana data source
  └→ Log into AMG workspace
  └→ Add AMP as Prometheus data source (use workspace endpoint)
  └→ Import GPU fleet dashboard
```

### 3.3 Files to Change

| File | Change |
|------|--------|
| `modules/monitoring/main.tf` | Check/fix AMG auth method based on SSO availability. Fix `permission_type`/`role_arn` conflict. Add `aws_prometheus_alert_manager_definition`. Fix S3 replication alarm dimensions (or defer). Optionally add SNS topic. |
| `modules/monitoring/variables.tf` | Add `grafana_auth_providers` variable with default, so auth can be switched. Add `s3_replication_bucket_name` and `s3_replication_rule_id` for alarm dimensions. |
| `modules/eks-cluster/main.tf` | Add ADOT IRSA role (similar to ALB Controller IRSA). |
| `gitops/add-ons/adot-collector.yaml` | **NEW** — ArgoCD Application for ADOT Collector with AMP remote write config. |
| `gitops/add-ons/dcgm-exporter.yaml` | **NEW** — ArgoCD Application for DCGM Exporter DaemonSet. |
| `gitops/add-ons/kustomization.yaml` | Add adot-collector.yaml and dcgm-exporter.yaml to resources list. |

---

## 4. Item 3: Claude Code Skills

### 4.1 Gap Analysis

**What exists:**
- `skills/capacity-blocks/SKILL.md` — complete skill definition with 5 commands (search, buy, list, status, extend)
- `skills/training-plans/SKILL.md` — complete skill definition with 4 commands (search, buy, list, status)

**What needs validation:**

#### Validation 1: CLI command accuracy
The SKILL.md files reference specific AWS CLI commands. Verify these are correct:

| Command | API | Status |
|---------|-----|--------|
| `aws ec2 describe-capacity-block-offerings` | `ec2:DescribeCapacityBlockOfferings` | Exists — available since 2024 |
| `aws ec2 purchase-capacity-block` | `ec2:PurchaseCapacityBlock` | Exists |
| `aws ec2 describe-capacity-reservations --filters capacity-reservation-type=capacity-block` | Standard EC2 API | Correct |
| `aws sagemaker search-training-plan-offerings` | `sagemaker:SearchTrainingPlanOfferings` | **Verify** — this is a newer API |
| `aws sagemaker create-training-plan` | `sagemaker:CreateTrainingPlan` | **Verify** |
| `aws sagemaker list-training-plans` | `sagemaker:ListTrainingPlans` | **Verify** |
| `aws sagemaker describe-training-plan` | `sagemaker:DescribeTrainingPlan` | **Verify** |

#### Validation 2: Skill registration
Claude Code skills need to be registered. The skills directory is at `skills/` in the repo root. For Claude Code to discover them, the `CLAUDE.md` or `.claude/settings.json` must reference this directory, or the skills must be in `.claude/skills/`.

**Check:** Where does Claude Code look for custom skills? The standard location is `.claude/commands/` or the skills must be registered in project settings.

#### Validation 3: Cross-account role assumption
Both skills reference cross-account operations (account 159553542841). The `aws sts assume-role` call requires the target account's `TerraformExecutionRole` to trust the source account/principal. **This doesn't exist yet for the secondary account** — these commands will fail for cross-account queries.

**Mitigation:** Skills should gracefully handle the secondary account being unavailable and only query the main account (483026362307).

### 4.2 Deployment Sequence

```
Step 1: Validate CLI commands
  └→ Run each search command against the main account
  └→ aws ec2 describe-capacity-block-offerings --instance-type p5.48xlarge --instance-count 8 --capacity-duration-hours 168 --region us-east-1
  └→ aws sagemaker search-training-plan-offerings (verify API exists in CLI version)

Step 2: Register skills with Claude Code
  └→ Move or symlink skills/ to .claude/commands/ (or configure in settings)
  └→ Verify /capacity-blocks and /training-plans appear in Claude Code

Step 3: End-to-end test
  └→ /capacity-blocks search --type p5.48xlarge --count 8 --days 7 --region us-east-1
  └→ /capacity-blocks list
  └→ /training-plans search --type ml.p5.48xlarge --count 8 --hours 168 --region us-east-1
  └→ /training-plans list
```

### 4.3 Files to Change

| File | Change |
|------|--------|
| `skills/capacity-blocks/SKILL.md` | Fix any incorrect CLI commands after validation. Add error handling for unavailable secondary account. |
| `skills/training-plans/SKILL.md` | Verify SageMaker Training Plans CLI commands exist. Fix if API names differ. |
| `.claude/settings.json` or `CLAUDE.md` | Register skills directory if not already configured. |

---

## 5. Recommended Deployment Order

```
┌──────────────────────────────────────────────────────────────────────────┐
│ All three items can run in parallel (no dependencies between them)        │
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │ ParallelCluster   │  │ Monitoring stack  │  │ Claude Code skills   │  │
│  │ (fix provider →   │  │ (terragrunt apply │  │ (validate + register)│  │
│  │  apply → validate)│  │  + ADOT pipeline) │  │                      │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

**Rationale:** All three items are independent. TerraformExecutionRole has AdministratorAccess so ParallelCluster has no IAM blocker. Recommended sequence: monitoring first (for observability), then ParallelCluster (longest apply time), skills in parallel.

---

## 6. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| IAM Identity Center not enabled → AMG fails | Monitoring partially broken | Deploy AMP only; switch AMG to SAML auth via Cognito |
| ParallelCluster API deploy fails (CFN timeout) | No cluster created | Check CloudFormation events; common cause is Lambda deployment size limits |
| Capacity Block queue with empty reservation ID | Cluster creation fails | Remove capacity-block queue from initial config |
| Capacity Block AZ doesn't match subnet AZ | Reservation unusable by ParallelCluster | Document constraint: purchase CB in same AZ as compute subnet *(Codex #4)* |
| SageMaker Training Plans API not in CLI | Skills fail | Verify `aws sagemaker` subcommands exist in installed CLI version; upgrade if needed |
| GPU nodes not available (p5.48xlarge) | Compute fleet stays at 0 (on-demand queue) or fails to place (capacity-block MinCount=8) | Expected for on-demand; for capacity-block, queue is removed on initial deploy |
| AMP alerts route nowhere | Silent failures | Add `aws_prometheus_alert_manager_definition` with SNS receiver *(Codex #5)* |
| S3 replication alarm never fires | False sense of safety | Add `BucketName`/`RuleId` dimensions, or defer until replication configured *(Codex #6)* |

---

## 7. Validation Checklist

### ParallelCluster
- [ ] CloudFormation stack `pcluster-api-us-east-1` exists and status is `CREATE_COMPLETE`
- [ ] `pcluster list-clusters --region us-east-1` shows `training` cluster
- [ ] Head node reachable via SSM: `aws ssm start-session --target <head-node-instance-id>`
- [ ] `sinfo` shows `gpu-ondemand` queue with `p5.48xlarge` node type
- [ ] `/fsx` mounted (FSx Lustre) and `/home` mounted (EFS)
- [ ] `srun --partition=gpu-ondemand --nodes=1 --gres=gpu:8 hostname` (if nodes available)

### Monitoring
- [ ] AMP workspace ID in Terraform output
- [ ] `aws amp list-workspaces` shows `ml-monitoring-main-us-east-1`
- [ ] CloudWatch alarms exist: `aws cloudwatch describe-alarms --alarm-name-prefix subnet-ip-exhaustion`
- [ ] AMG workspace accessible (if SSO is available)
- [ ] ADOT pods running in kube-system (after ArgoCD sync)
- [ ] Metrics visible in AMP: `aws amp query --workspace-id <id> --query 'up'`

### Claude Code Skills
- [ ] `/capacity-blocks search` returns results (or "no offerings" — both are valid)
- [ ] `/capacity-blocks list` completes without error for main account
- [ ] `/training-plans search` completes without error
- [ ] `/training-plans list` completes without error

---

## 8. Codex Second Opinion — Review Summary

10 findings reviewed, 7 accepted, 3 rejected. Changes incorporated above.

| # | Finding | Verdict | Rationale |
|---|---------|---------|-----------|
| 1 | `versions.tf` already exists | **Accept** | Confirmed — removed Fix 4 |
| 2 | TerraformExecutionRole has AdministratorAccess | **Accept** | Confirmed at iam/main.tf:94 — removed IAM dependency |
| 3 | Architecture mismatch (create vs reuse infra) | **Reject** | Modules *created* the VPC/FSx/EFS; listed IDs are their outputs |
| 4 | Single-AZ compute / Capacity Block AZ match | **Accept (partial)** | Single-AZ correct for EFA; added AZ-match documentation note |
| 5 | No Alertmanager definition for AMP | **Accept** | Added Fix 4 to monitoring section |
| 6 | S3 replication alarm missing dimensions | **Accept** | Added Fix 5 to monitoring section |
| 7 | AMG permission_type + role_arn conflict | **Accept (partial)** | Added Fix 6, needs investigation during apply |
| 8 | MinCount=8 contradicts "stays at 0" risk | **Accept** | Fixed risk table text |
| 9 | Unused vpc_id/eks_cluster_name in monitoring | **Accept** | Noted — will be used when wiring ADOT |
| 10 | Cross-account skills fail | **Reject** | Already documented in Section 4.1 Validation 3 |
