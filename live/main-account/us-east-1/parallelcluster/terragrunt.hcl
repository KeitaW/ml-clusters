include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/parallelcluster.hcl"
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

generate "parallelcluster_provider" {
  path      = "parallelcluster_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws-parallelcluster" {
      region   = "us-east-1"
      endpoint = "https://pcluster-api.us-east-1.amazonaws.com"
    }

    terraform {
      required_providers {
        aws-parallelcluster = {
          source  = "aws-tf/aws-parallelcluster"
          version = "~> 1.1"
        }
      }
    }
  EOF
}

inputs = {
  region              = "us-east-1"
  deploy_pcluster_api = true
  cluster_configs = {
    training = {
      config_path        = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../cluster-configs/parallelcluster/training-cluster.yaml"
      head_node_subnet_id    = dependency.networking.outputs.public_subnet_ids[0]
      compute_subnet_id      = dependency.networking.outputs.private_subnet_ids[0]
      fsx_filesystem_id      = dependency.shared_storage.outputs.fsx_filesystem_id
      efs_filesystem_id      = dependency.shared_storage.outputs.efs_filesystem_id
    }
  }
}
