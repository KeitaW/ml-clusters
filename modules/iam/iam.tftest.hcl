mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  account_name                    = "test"
  aws_region                      = "us-east-1"
  create_terraform_execution_role = true
  create_parallelcluster_roles    = true
  create_hyperpod_role            = true
  create_s3_replication_role      = false
}

run "kms_key_configuration" {
  command = plan

  assert {
    condition     = aws_kms_key.shared.enable_key_rotation == true
    error_message = "KMS key must have automatic rotation enabled"
  }

  assert {
    condition     = aws_kms_key.shared.deletion_window_in_days == 30
    error_message = "KMS key deletion window should be 30 days"
  }

  assert {
    condition     = aws_kms_key.shared.description == "Shared KMS key for ml-test-us-east-1"
    error_message = "KMS key description should follow naming convention"
  }

  assert {
    condition     = aws_kms_alias.shared.name == "alias/ml-test-us-east-1"
    error_message = "KMS alias should follow alias/ml-{account}-{region} convention"
  }
}

run "all_roles_created" {
  command = plan

  assert {
    condition     = length(aws_iam_role.terraform_execution) == 1
    error_message = "Terraform execution role should be created when enabled"
  }

  assert {
    condition     = aws_iam_role.terraform_execution[0].name == "TerraformExecutionRole"
    error_message = "Terraform execution role name should be TerraformExecutionRole"
  }

  assert {
    condition     = length(aws_iam_role.parallelcluster_head_node) == 1
    error_message = "ParallelCluster head node role should be created when enabled"
  }

  assert {
    condition     = aws_iam_role.parallelcluster_head_node[0].name == "ParallelClusterHeadNodeRole"
    error_message = "Head node role name should be ParallelClusterHeadNodeRole"
  }

  assert {
    condition     = length(aws_iam_role.parallelcluster_compute) == 1
    error_message = "ParallelCluster compute role should be created when enabled"
  }

  assert {
    condition     = aws_iam_role.parallelcluster_compute[0].name == "ParallelClusterComputeRole"
    error_message = "Compute role name should be ParallelClusterComputeRole"
  }

  assert {
    condition     = length(aws_iam_role.hyperpod_execution) == 1
    error_message = "HyperPod execution role should be created when enabled"
  }

  assert {
    condition     = aws_iam_role.hyperpod_execution[0].name == "HyperPodExecutionRole"
    error_message = "HyperPod role name should be HyperPodExecutionRole"
  }

  assert {
    condition     = length(aws_iam_role.s3_replication) == 0
    error_message = "S3 replication role should NOT be created when disabled"
  }
}

run "no_optional_roles" {
  command = plan

  variables {
    create_terraform_execution_role = false
    create_parallelcluster_roles    = false
    create_hyperpod_role            = false
    create_s3_replication_role      = false
  }

  assert {
    condition     = length(aws_iam_role.terraform_execution) == 0
    error_message = "No Terraform role when disabled"
  }

  assert {
    condition     = length(aws_iam_role.parallelcluster_head_node) == 0
    error_message = "No ParallelCluster head node role when disabled"
  }

  assert {
    condition     = length(aws_iam_role.parallelcluster_compute) == 0
    error_message = "No ParallelCluster compute role when disabled"
  }

  assert {
    condition     = length(aws_iam_role.hyperpod_execution) == 0
    error_message = "No HyperPod role when disabled"
  }

  assert {
    condition     = length(aws_iam_role.s3_replication) == 0
    error_message = "No S3 replication role when disabled"
  }
}

run "s3_replication_role" {
  command = plan

  variables {
    create_terraform_execution_role = false
    create_parallelcluster_roles    = false
    create_hyperpod_role            = false
    create_s3_replication_role      = true
    s3_source_bucket_arn            = "arn:aws:s3:::source-bucket"
    s3_destination_bucket_arns      = ["arn:aws:s3:::dest-bucket-west", "arn:aws:s3:::dest-bucket-secondary"]
    kms_key_arns                    = ["arn:aws:kms:us-west-2:123456789012:key/west-key"]
  }

  assert {
    condition     = length(aws_iam_role.s3_replication) == 1
    error_message = "S3 replication role should be created when enabled"
  }

  assert {
    condition     = aws_iam_role.s3_replication[0].name == "S3ReplicationRole"
    error_message = "S3 replication role name should be S3ReplicationRole"
  }
}
