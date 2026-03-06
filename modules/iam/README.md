# iam

KMS keys and IAM roles for ML cluster infrastructure.

## Overview

Creates a shared KMS key and optional IAM roles for various cluster components. Roles are conditionally created based on feature flags, supporting Terraform execution, ParallelCluster, HyperPod, S3 replication, and ArgoCD cross-account spoke access. The KMS key is consumed by S3, FSx, EFS, and other modules for encryption at rest.

## Resources Created

- Shared KMS key with auto-rotation and optional cross-account access
- KMS alias (`alias/ml-{account_name}-{region}`)
- TerraformExecutionRole with AdministratorAccess (optional)
- ParallelCluster head node and compute IAM roles (optional)
- HyperPod execution role with SageMaker, S3, FSx, VPC, KMS permissions (optional)
- HyperPod Karpenter autoscaling role (optional)
- S3 replication role with cross-region/account KMS permissions (optional)
- ArgoCD spoke access role for cross-account hub authentication (optional)

## Usage

```hcl
# live/_envcommon/iam.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/iam"
}

inputs = {
  account_name                    = "main"
  aws_region                      = "us-east-1"
  create_terraform_execution_role = false  # bootstrapped manually
  create_hyperpod_role            = true
  create_parallelcluster_roles    = true
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `account_name` | `string` | — | Yes | Account name for resource naming |
| `aws_region` | `string` | — | Yes | AWS region |
| `cross_account_ids` | `list(string)` | `[]` | No | Account IDs for cross-account KMS access |
| `create_terraform_execution_role` | `bool` | `true` | No | Create the TerraformExecutionRole |
| `terraform_execution_trust_account_ids` | `list(string)` | `[]` | No | Account IDs allowed to assume TerraformExecutionRole |
| `create_parallelcluster_roles` | `bool` | `false` | No | Create ParallelCluster IAM roles |
| `create_hyperpod_role` | `bool` | `false` | No | Create HyperPod execution role |
| `create_hyperpod_karpenter_role` | `bool` | `false` | No | Create HyperPod Karpenter autoscaling role |
| `create_s3_replication_role` | `bool` | `false` | No | Create S3 replication role |
| `s3_source_bucket_arn` | `string` | `""` | No | Source S3 bucket ARN for replication |
| `s3_destination_bucket_arns` | `list(string)` | `[]` | No | Destination S3 bucket ARNs for replication |
| `kms_key_arns` | `list(string)` | `[]` | No | Destination KMS key ARNs for replication encryption |
| `create_argocd_spoke_role` | `bool` | `false` | No | Create ArgoCD spoke access role |
| `argocd_hub_role_arn` | `string` | `""` | No | ArgoCD hub controller IRSA role ARN |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `kms_key_arn` | ARN of the shared KMS key |
| `kms_key_id` | ID of the shared KMS key |
| `terraform_execution_role_arn` | ARN of the TerraformExecutionRole |
| `parallelcluster_head_node_role_arn` | ARN of the ParallelCluster head node role |
| `parallelcluster_compute_role_arn` | ARN of the ParallelCluster compute role |
| `hyperpod_execution_role_arn` | ARN of the HyperPod execution role |
| `hyperpod_karpenter_role_arn` | ARN of the HyperPod Karpenter role |
| `s3_replication_role_arn` | ARN of the S3 replication role |
| `argocd_spoke_access_role_arn` | ARN of the ArgoCD spoke access role |

## Dependencies

- None — this is a foundational module
- Required providers: `hashicorp/aws ~> 6.0`
