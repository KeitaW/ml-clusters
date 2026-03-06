# hyperpod

SageMaker HyperPod cluster with Slurm or EKS orchestration.

## Overview

Creates a SageMaker HyperPod cluster supporting both Slurm and EKS orchestrators. Configures instance groups with optional GPU health checks, EFA networking, and per-group VPC overrides. For Slurm orchestration, uploads lifecycle scripts and provisioning parameters to S3. For EKS orchestration, supports Karpenter-based autoscaling. Includes CloudWatch log group for cluster diagnostics.

## Resources Created

- SageMaker HyperPod cluster (via `awscc_sagemaker_cluster`)
- Instance groups with configurable instance types, counts, EBS volumes, and health checks
- CloudWatch log group (when `create_cloudwatch_log_group` is true)
- S3 objects for lifecycle scripts (when `lifecycle_scripts_s3_bucket` is set)
- S3 object for Slurm provisioning parameters JSON (when using Slurm orchestrator)

## Usage

```hcl
# live/_envcommon/hyperpod.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/hyperpod"
}

inputs = {
  cluster_name          = "ml-hyperpod-secondary-us-west-2"
  orchestrator          = "slurm"
  aws_region            = "us-west-2"
  execution_role_arn    = dependency.iam.outputs.hyperpod_execution_role_arn
  vpc_id                = dependency.networking.outputs.vpc_id
  private_subnet_ids    = dependency.networking.outputs.private_subnet_ids
  efa_security_group_id = dependency.networking.outputs.efa_security_group_id

  instance_groups = [
    {
      instance_group_name = "controller"
      instance_type       = "ml.m5.xlarge"
      instance_count      = 1
      life_cycle_config = {
        source_s3_uri = "s3://my-bucket/hyperpod/lifecycle-scripts"
        on_create     = "on_create.sh"
      }
    }
  ]

  lifecycle_scripts_s3_bucket = "my-bucket"
  fsx_filesystem_id           = dependency.shared_storage.outputs.fsx_filesystem_id
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `cluster_name` | `string` | — | Yes | HyperPod cluster name (1-63 chars) |
| `orchestrator` | `string` | `"slurm"` | No | Orchestrator type: `slurm` or `eks` |
| `aws_region` | `string` | — | Yes | AWS region |
| `node_recovery` | `string` | `"Automatic"` | No | Node recovery mode: `Automatic` or `None` |
| `execution_role_arn` | `string` | — | Yes | Default IAM execution role ARN |
| `vpc_id` | `string` | — | Yes | VPC ID |
| `private_subnet_ids` | `list(string)` | — | Yes | Private subnet IDs |
| `efa_security_group_id` | `string` | — | Yes | EFA security group ID |
| `instance_groups` | `list(object)` | — | Yes | Instance group configurations |
| `eks_cluster_arn` | `string` | `""` | No | EKS cluster ARN (required for EKS orchestrator) |
| `enable_eks_autoscaling` | `bool` | `false` | No | Enable Karpenter autoscaling (EKS only) |
| `eks_autoscaling_role_arn` | `string` | `""` | No | Karpenter autoscaling role ARN |
| `lifecycle_scripts_s3_bucket` | `string` | `""` | No | S3 bucket for lifecycle scripts |
| `lifecycle_scripts_s3_prefix` | `string` | `"hyperpod/lifecycle-scripts"` | No | S3 key prefix |
| `lifecycle_scripts_path` | `string` | `"lifecycle-scripts"` | No | Local path to lifecycle scripts |
| `slurm_provisioning_parameters` | `object` | `null` | No | Slurm provisioning params |
| `fsx_filesystem_id` | `string` | `""` | No | FSx Lustre filesystem ID |
| `create_cloudwatch_log_group` | `bool` | `true` | No | Create CloudWatch log group |
| `log_retention_days` | `number` | `30` | No | Log retention in days |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_arn` | HyperPod cluster ARN |
| `cluster_name` | HyperPod cluster name |
| `cluster_status` | HyperPod cluster status |
| `orchestrator` | Orchestrator type |
| `cloudwatch_log_group_name` | CloudWatch log group name |
| `lifecycle_scripts_s3_uri` | S3 URI for lifecycle scripts |

## Dependencies

- **networking**: `vpc_id`, `private_subnet_ids`, `efa_security_group_id`
- **iam**: `execution_role_arn` (`hyperpod_execution_role_arn`)
- **eks-cluster** (EKS orchestrator): `cluster_arn`
- **shared-storage** (optional): `fsx_filesystem_id`
- Required providers: `hashicorp/aws ~> 6.0`, `hashicorp/awscc >= 1.25.0`
