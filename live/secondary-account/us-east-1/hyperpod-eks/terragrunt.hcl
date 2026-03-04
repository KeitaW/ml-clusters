include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/hyperpod.hcl"
  expose = true
}

dependency "networking" {
  config_path = "../networking"
}

dependency "iam" {
  config_path = "../iam"
}

dependency "shared_storage" {
  config_path = "../shared-storage"
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"
}

generate "awscc_provider" {
  path      = "awscc_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "awscc" {
      region = "us-east-1"

      assume_role = {
        role_arn = "arn:aws:iam::159553542841:role/TerraformExecutionRole"
      }
    }
  EOF
}

inputs = {
  cluster_name            = "ml-hyperpod-eks-secondary-us-east-1"
  orchestrator            = "eks"
  eks_cluster_arn         = dependency.eks_cluster.outputs.cluster_arn
  execution_role_arn      = dependency.iam.outputs.hyperpod_execution_role_arn
  vpc_id                  = dependency.networking.outputs.vpc_id
  private_subnet_ids      = dependency.networking.outputs.private_subnet_ids
  efa_security_group_id   = dependency.networking.outputs.efa_security_group_id
  fsx_filesystem_id       = dependency.shared_storage.outputs.fsx_filesystem_id

  # Lifecycle scripts for EKS
  lifecycle_scripts_s3_bucket  = "ml-data-replica-159553542841-us-east-1"
  lifecycle_scripts_local_path = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../cluster-configs/hyperpod/lifecycle-scripts/eks-config"

  # Karpenter autoscaling
  auto_scaling_enabled   = true
  cluster_role_arn       = dependency.iam.outputs.hyperpod_karpenter_role_arn
  node_provisioning_mode = "Continuous"

  # Start with system group only; GPU groups added when quota confirmed
  instance_groups = [
    {
      instance_group_name = "system"
      instance_type       = "ml.m5.xlarge"
      instance_count      = 1
      life_cycle_config = {
        source_s3_uri = "s3://ml-data-replica-159553542841-us-east-1/hyperpod/lifecycle-scripts/"
        on_create     = "on_create.sh"
      }
    },
  ]
}
