mock_provider "aws" {}

variables {
  source_bucket_id = "ml-central-data-bucket"
  iam_role_arn     = "arn:aws:iam::123456789012:role/S3ReplicationRole"
  replication_rules = [
    {
      id                      = "datasets-to-west"
      prefix                  = "datasets/"
      destination_bucket_arn  = "arn:aws:s3:::ml-data-west"
      destination_account_id  = "123456789012"
      destination_kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/west-key"
      storage_class           = "STANDARD"
    },
    {
      id                      = "checkpoints-to-west"
      prefix                  = "checkpoints/"
      destination_bucket_arn  = "arn:aws:s3:::ml-data-west"
      destination_account_id  = "123456789012"
      destination_kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/west-key"
      storage_class           = "STANDARD"
    },
    {
      id                      = "models-to-secondary"
      prefix                  = "models/"
      destination_bucket_arn  = "arn:aws:s3:::ml-data-secondary"
      destination_account_id  = "159553542841"
      destination_kms_key_arn = "arn:aws:kms:us-west-2:159553542841:key/sec-key"
      storage_class           = "STANDARD"
    },
  ]
}

run "replication_source" {
  command = plan

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.bucket == "ml-central-data-bucket"
    error_message = "Replication should be configured on the source bucket"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.role == "arn:aws:iam::123456789012:role/S3ReplicationRole"
    error_message = "Replication should use the provided IAM role"
  }
}

run "replication_rules_count" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.this.rule) == 3
    error_message = "Should create 3 replication rules from input"
  }
}

run "replication_rule_config" {
  command = plan

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].id == "datasets-to-west"
    error_message = "First rule ID should match input"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].status == "Enabled"
    error_message = "All replication rules should be enabled"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].filter[0].prefix == "datasets/"
    error_message = "First rule should filter on datasets/ prefix"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].delete_marker_replication[0].status == "Enabled"
    error_message = "Delete marker replication should be enabled for consistency"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].destination[0].bucket == "arn:aws:s3:::ml-data-west"
    error_message = "Destination bucket ARN should match input"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this.rule[0].destination[0].account == "123456789012"
    error_message = "Destination account should match input"
  }
}
