provider "aws" {
  region = "us-east-1"
}

variables {
  bucket_name = "test-ml-data-bucket"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test-key-id"
}

run "bucket_created_with_versioning" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "test-ml-data-bucket"
    error_message = "Bucket should be created with correct name"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled"
  }
}

run "public_access_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "Public ACLs should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "Public policy should be blocked"
  }
}
