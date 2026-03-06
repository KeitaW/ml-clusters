# shared-storage

FSx for Lustre and EFS shared filesystems for ML workloads.

## Overview

Provisions FSx for Lustre (PERSISTENT_2 with LZ4 compression) and EFS (elastic throughput) filesystems shared across EKS, ParallelCluster, and HyperPod clusters. FSx includes a data repository association that auto-imports/exports data to/from S3 at the `/data` mount path. EFS provides an access point at `/home` for user home directories.

## Resources Created

- FSx for Lustre filesystem (PERSISTENT_2, LZ4 compression, configurable capacity and throughput)
- FSx security group (Lustre ports 988, 1021-1023 from VPC CIDR)
- FSx data repository association (auto-import/export NEW, CHANGED, DELETED to S3)
- EFS filesystem (encrypted, elastic throughput, generalPurpose)
- EFS mount targets (one per private subnet)
- EFS security group (NFS port 2049 from VPC CIDR)
- EFS access point (`/home`, UID/GID 1000, permissions 755)

## Usage

```hcl
# live/_envcommon/shared-storage.hcl
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/shared-storage"
}

inputs = {
  account_name       = "main"
  aws_region         = "us-east-1"
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids
  kms_key_arn        = dependency.iam.outputs.kms_key_arn
  s3_data_bucket_arn = dependency.s3_data_bucket.outputs.bucket_arn
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `account_name` | `string` | — | Yes | Account name for resource naming |
| `aws_region` | `string` | — | Yes | AWS region |
| `vpc_id` | `string` | — | Yes | VPC ID |
| `private_subnet_ids` | `list(string)` | — | Yes | Private subnet IDs for mount targets |
| `kms_key_arn` | `string` | `null` | No | KMS key ARN for encryption |
| `s3_data_bucket_arn` | `string` | — | Yes | S3 bucket ARN for FSx data repository association |
| `fsx_storage_capacity` | `number` | `4800` | No | FSx storage capacity in GiB (multiple of 2400) |
| `fsx_throughput_per_unit` | `number` | `500` | No | Throughput per unit in MB/s/TiB (125, 250, 500, 1000) |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `fsx_filesystem_id` | ID of the FSx for Lustre filesystem |
| `fsx_filesystem_arn` | ARN of the FSx for Lustre filesystem |
| `fsx_dns_name` | DNS name of the FSx for Lustre filesystem |
| `fsx_mount_name` | Mount name of the FSx for Lustre filesystem |
| `efs_filesystem_id` | ID of the EFS filesystem |
| `efs_filesystem_arn` | ARN of the EFS filesystem |
| `efs_access_point_id` | ID of the EFS access point for /home |

## Dependencies

- **networking**: `vpc_id`, `private_subnet_ids`
- **iam**: `kms_key_arn`
- **s3-data-bucket**: `s3_data_bucket_arn`
- Required providers: `hashicorp/aws ~> 6.0`
