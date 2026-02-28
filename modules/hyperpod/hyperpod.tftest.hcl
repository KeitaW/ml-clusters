mock_provider "aws" {}
mock_provider "awscc" {}

variables {
  cluster_name          = "test-hyperpod"
  orchestrator          = "slurm"
  aws_region            = "us-east-1"
  execution_role_arn    = "arn:aws:iam::123456789012:role/HyperPodExecutionRole"
  vpc_id                = "vpc-test12345"
  private_subnet_ids    = ["subnet-a"]
  efa_security_group_id = "sg-efa12345"
  instance_groups = [
    {
      instance_group_name = "gpu-workers"
      instance_type       = "ml.p5.48xlarge"
      instance_count      = 4
      life_cycle_config = {
        source_s3_uri = "s3://lifecycle-bucket/scripts/"
        on_create     = "on_create.sh"
      }
    }
  ]
}

run "slurm_cluster" {
  command = plan

  assert {
    condition     = awscc_sagemaker_cluster.this.cluster_name == "test-hyperpod"
    error_message = "Cluster name should match input"
  }

  assert {
    condition     = awscc_sagemaker_cluster.this.node_recovery == "Automatic"
    error_message = "Node recovery should be Automatic for resilient training"
  }
}

run "eks_orchestrator_requires_arn" {
  command = plan

  variables {
    orchestrator    = "eks"
    eks_cluster_arn = ""
  }

  expect_failures = [
    awscc_sagemaker_cluster.this,
  ]
}

run "eks_orchestrator_with_arn" {
  command = plan

  variables {
    orchestrator    = "eks"
    eks_cluster_arn = "arn:aws:eks:us-east-1:123456789012:cluster/ml-eks"
  }

  assert {
    condition     = awscc_sagemaker_cluster.this.cluster_name == "test-hyperpod"
    error_message = "EKS-orchestrated cluster should be created when ARN provided"
  }
}
