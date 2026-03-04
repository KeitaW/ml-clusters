mock_provider "aws" {}
mock_provider "awscc" {}

###############################################################################
# Slurm Orchestration
###############################################################################

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
      instance_group_name = "controller"
      instance_type       = "ml.m5.xlarge"
      instance_count      = 1
      life_cycle_config = {
        source_s3_uri = "s3://sagemaker-lifecycle-bucket/scripts/"
        on_create     = "on_create.sh"
      }
    },
    {
      instance_group_name         = "gpu-workers"
      instance_type               = "ml.p5.48xlarge"
      instance_count              = 4
      min_instance_count          = 2
      ebs_volume_size_gb          = 500
      on_start_deep_health_checks = ["InstanceStress", "InstanceConnectivity"]
      life_cycle_config = {
        source_s3_uri = "s3://sagemaker-lifecycle-bucket/scripts/"
        on_create     = "on_create.sh"
      }
    }
  ]
}

run "slurm_cluster_name" {
  command = plan

  assert {
    condition     = awscc_sagemaker_cluster.this.cluster_name == "test-hyperpod"
    error_message = "Cluster name should match input"
  }
}

run "slurm_node_recovery" {
  command = plan

  assert {
    condition     = awscc_sagemaker_cluster.this.node_recovery == "Automatic"
    error_message = "Node recovery should be Automatic for resilient training"
  }
}

run "slurm_uses_slurm_orchestrator" {
  command = plan

  assert {
    condition     = var.orchestrator == "slurm"
    error_message = "Orchestrator should be slurm"
  }
}

run "slurm_instance_group_count" {
  command = plan

  assert {
    condition     = length(awscc_sagemaker_cluster.this.instance_groups) == 2
    error_message = "Should have 2 instance groups (controller + gpu-workers)"
  }
}

run "cloudwatch_log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.cluster[0].name == "/aws/sagemaker/Clusters/test-hyperpod"
    error_message = "CloudWatch log group should follow /aws/sagemaker/Clusters/{name} pattern"
  }
}

run "no_autoscaling_for_slurm" {
  command = plan

  assert {
    condition     = var.enable_eks_autoscaling == false
    error_message = "EKS autoscaling should be disabled for Slurm orchestrator"
  }
}

###############################################################################
# EKS Orchestration
###############################################################################

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
    instance_groups = [
      {
        instance_group_name = "gpu-workers"
        instance_type       = "ml.p5.48xlarge"
        instance_count      = 2
        life_cycle_config = {
          source_s3_uri = "s3://sagemaker-lifecycle-bucket/scripts/"
          on_create     = "on_create.sh"
        }
        kubernetes_config = {
          labels = {
            "node.kubernetes.io/role" = "gpu-worker"
          }
          taints = [
            {
              key    = "nvidia.com/gpu"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
        }
      }
    ]
  }

  assert {
    condition     = awscc_sagemaker_cluster.this.cluster_name == "test-hyperpod"
    error_message = "EKS-orchestrated cluster should be created when ARN provided"
  }
}

run "eks_autoscaling_requires_eks" {
  command = plan

  variables {
    orchestrator             = "slurm"
    enable_eks_autoscaling   = true
    eks_autoscaling_role_arn = "arn:aws:iam::123456789012:role/KarpenterRole"
  }

  expect_failures = [
    awscc_sagemaker_cluster.this,
  ]
}

###############################################################################
# Validation
###############################################################################

run "invalid_orchestrator_type" {
  command = plan

  variables {
    orchestrator = "kubernetes"
  }

  expect_failures = [
    var.orchestrator,
  ]
}

run "cluster_name_validation" {
  command = plan

  variables {
    cluster_name = ""
  }

  expect_failures = [
    var.cluster_name,
  ]
}

run "disable_cloudwatch_log_group" {
  command = plan

  variables {
    create_cloudwatch_log_group = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.cluster) == 0
    error_message = "CloudWatch log group should not be created when disabled"
  }
}
