provider "aws" {
  region = "us-east-1"
}

variables {
  account_name                   = "test"
  aws_region                     = "us-east-1"
  create_terraform_execution_role = true
  create_parallelcluster_roles   = true
  create_hyperpod_role           = true
  create_s3_replication_role     = false
}

run "kms_key_created" {
  command = plan

  assert {
    condition     = aws_kms_key.shared.description != ""
    error_message = "KMS key should be created"
  }
}

run "terraform_role_created" {
  command = plan

  assert {
    condition     = length(aws_iam_role.terraform_execution) == 1
    error_message = "Terraform execution role should be created when enabled"
  }
}

run "parallelcluster_roles_created" {
  command = plan

  assert {
    condition     = length(aws_iam_role.parallelcluster_head_node) == 1
    error_message = "ParallelCluster head node role should be created when enabled"
  }
}

run "hyperpod_role_created" {
  command = plan

  assert {
    condition     = length(aws_iam_role.hyperpod_execution) == 1
    error_message = "HyperPod execution role should be created when enabled"
  }
}
