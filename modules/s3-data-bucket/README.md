# s3-data-bucket

Central ML data bucket with versioning, encryption, and lifecycle management.

## Overview

Creates an S3 bucket configured for ML data storage with versioning enabled, configurable KMS or AES256 encryption, public access blocking, and lifecycle rules. Supports acting as a replication destination by granting access to replication source role ARNs. The `models/` prefix transitions to STANDARD_IA after 30 days.

## Resources Created

- S3 bucket with versioning enabled
- Server-side encryption (SSE-KMS with bucket key, or AES256 fallback)
- Public access block (all four settings enabled)
- Bucket policy enforcing HTTPS and optional replication access
- Lifecycle rules: `models/` to STANDARD_IA at 30 days, abort incomplete multipart uploads at 7 days

## Usage

```hcl
# live/_envcommon/s3-data-bucket.hcl
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/s3-data-bucket"
}

inputs = {
  bucket_name = "ml-data-central-483026362307-us-east-1"
  kms_key_arn = dependency.iam.outputs.kms_key_arn
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `bucket_name` | `string` | — | Yes | Name of the S3 bucket |
| `kms_key_arn` | `string` | `null` | No | KMS key ARN for SSE-KMS encryption. When null, uses AES256. |
| `replication_source_role_arns` | `list(string)` | `[]` | No | IAM role ARNs allowed to replicate objects to this bucket |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | The name of the S3 bucket |
| `bucket_arn` | The ARN of the S3 bucket |
| `bucket_domain_name` | The bucket domain name |

## Dependencies

- **iam**: `kms_key_arn` for encryption
- Required providers: `hashicorp/aws ~> 6.0`
