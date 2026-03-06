# monitoring

Amazon Managed Prometheus, Grafana, SNS alerting, and CloudWatch alarms.

## Overview

Creates an AMP workspace for metrics storage, SNS topic for alert notifications, Prometheus alert rules (GPU idle, EFA stalled, FSx IOPS), and CloudWatch alarms for subnet IP exhaustion and S3 replication lag. Optionally provisions an Amazon Managed Grafana workspace with IAM Identity Center RBAC, AMP/CloudWatch read access, and a Terraform service account for programmatic dashboard management.

## Resources Created

- Amazon Managed Prometheus (AMP) workspace
- SNS topic with email subscription for alarm notifications
- Alertmanager definition routing alerts to SNS
- Prometheus alert rules: GPUIdle, EFAStalled, FSxIOPSHigh
- CloudWatch alarms for subnet IP exhaustion (one per subnet)
- CloudWatch alarm for S3 replication lag (when `s3_replication_bucket_name` is set)
- Amazon Managed Grafana workspace with IAM role (when `enable_grafana` is true)
- Grafana RBAC: admin/editor/viewer role associations (when Grafana is enabled)
- Grafana Terraform service account and API token (30-day TTL, when Grafana is enabled)

## Usage

```hcl
# live/main-account/us-east-1/monitoring/terragrunt.hcl
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/monitoring"
}

inputs = {
  account_name       = "main"
  aws_region         = "us-east-1"
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids
  notification_email = "alerts@example.com"
  enable_grafana     = true
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `account_name` | `string` | — | Yes | Account name for resource naming |
| `aws_region` | `string` | — | Yes | AWS region |
| `vpc_id` | `string` | — | Yes | VPC ID to monitor |
| `private_subnet_ids` | `list(string)` | — | Yes | Private subnet IDs for IP exhaustion alarms |
| `notification_email` | `string` | `""` | No | Email for SNS notifications |
| `enable_grafana` | `bool` | `false` | No | Create Amazon Managed Grafana workspace |
| `grafana_auth_providers` | `list(string)` | `["AWS_SSO"]` | No | Grafana authentication providers |
| `grafana_version` | `string` | `"10.4"` | No | Grafana workspace version |
| `grafana_admin_user_ids` | `list(string)` | `[]` | No | IAM Identity Center user IDs for ADMIN role |
| `grafana_editor_group_ids` | `list(string)` | `[]` | No | Identity Center group IDs for EDITOR role |
| `grafana_viewer_group_ids` | `list(string)` | `[]` | No | Identity Center group IDs for VIEWER role |
| `s3_replication_bucket_name` | `string` | `""` | No | Source S3 bucket for replication lag alarm |
| `s3_replication_dest_bucket_name` | `string` | `""` | No | Destination bucket for replication lag alarm |
| `s3_replication_rule_id` | `string` | `""` | No | S3 replication rule ID |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `amp_workspace_id` | AMP workspace ID |
| `amp_workspace_arn` | AMP workspace ARN |
| `amp_workspace_endpoint` | Prometheus endpoint URL |
| `amp_remote_write_endpoint` | Remote write endpoint URL |
| `sns_topic_arn` | SNS topic ARN for notifications |
| `grafana_workspace_id` | Grafana workspace ID (empty if disabled) |
| `grafana_workspace_endpoint` | Grafana endpoint URL (empty if disabled) |
| `grafana_workspace_arn` | Grafana workspace ARN (empty if disabled) |
| `grafana_service_account_token` | Grafana API token (sensitive, empty if disabled) |

## Dependencies

- **networking**: `vpc_id`, `private_subnet_ids`
- Required providers: `hashicorp/aws ~> 6.0`
