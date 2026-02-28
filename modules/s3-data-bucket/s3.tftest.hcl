mock_provider "aws" {}

variables {
  bucket_name = "test-ml-data-bucket"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test-key-id"
}

run "bucket_name" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "test-ml-data-bucket"
    error_message = "Bucket name should match input variable"
  }
}

run "versioning_enabled" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Bucket versioning must be enabled for data protection"
  }
}

run "public_access_fully_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "Public ACLs should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "Public policies should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == true
    error_message = "Public ACLs should be ignored"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    error_message = "Public bucket access should be restricted"
  }
}

run "sse_kms_encryption" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Encryption must use SSE-KMS algorithm"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/test-key-id"
    error_message = "Encryption should use the provided KMS key"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    error_message = "Bucket key should be enabled to reduce KMS API costs"
  }
}

run "lifecycle_rules" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "Should have 2 lifecycle rules (models-transition and abort-incomplete-uploads)"
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "models-transition"]) == 1
    error_message = "Should have a models-transition lifecycle rule"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "models-transition"]).status == "Enabled"
    error_message = "Models transition rule should be enabled"
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "abort-incomplete-uploads"]) == 1
    error_message = "Should have an abort-incomplete-uploads lifecycle rule"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "abort-incomplete-uploads"]).status == "Enabled"
    error_message = "Abort incomplete uploads rule should be enabled"
  }
}
