# s3-replication

Cross-region and cross-account S3 replication configuration.

## Overview

Configures S3 bucket replication rules on a source bucket to replicate objects to one or more destination buckets. Supports cross-region and cross-account replication with SSE-KMS encryption, S3 Replication Time Control (15-minute SLA), delete marker replication, and destination ownership override.

## Resources Created

- S3 bucket replication configuration with dynamic rules
  - Prefix-based filtering
  - SSE-KMS encryption for replicated objects
  - Ownership override to destination account
  - Replication Time Control enabled (15-minute SLA)
  - Delete marker replication enabled

## Usage

```hcl
# live/_envcommon/s3-replication.hcl (not yet in _envcommon)
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/s3-replication"
}

inputs = {
  source_bucket_id = dependency.s3_data_bucket.outputs.bucket_id
  iam_role_arn     = dependency.iam.outputs.s3_replication_role_arn

  replication_rules = [
    {
      id                      = "replicate-to-us-west-2"
      prefix                  = ""
      destination_bucket_arn  = "arn:aws:s3:::ml-data-replica-483026362307-us-west-2"
      destination_account_id  = "483026362307"
      destination_kms_key_arn = "arn:aws:kms:us-west-2:483026362307:key/example-key-id"
      storage_class           = "STANDARD"
    }
  ]
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `source_bucket_id` | `string` | — | Yes | ID (name) of the source S3 bucket |
| `iam_role_arn` | `string` | — | Yes | IAM role ARN for S3 replication |
| `replication_rules` | `list(object)` | — | Yes | List of replication rules (see below) |
| `tags` | `map(string)` | `{}` | No | Tags |

### `replication_rules` object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | Yes | Rule identifier |
| `prefix` | `string` | Yes | S3 key prefix filter (empty for all objects) |
| `destination_bucket_arn` | `string` | Yes | Destination bucket ARN |
| `destination_account_id` | `string` | Yes | Destination AWS account ID |
| `destination_kms_key_arn` | `string` | Yes | KMS key ARN in destination region |
| `storage_class` | `string` | No | Storage class (default: `STANDARD`) |

## Outputs

| Name | Description |
|------|-------------|
| `replication_configuration_id` | The ID of the S3 bucket replication configuration |

## Dependencies

- **s3-data-bucket**: `source_bucket_id` from the source bucket
- **iam**: `iam_role_arn` from the S3 replication role
- Required providers: `hashicorp/aws ~> 6.0`
