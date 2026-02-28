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

generate "awscc_provider" {
  path      = "awscc_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "awscc" {
      region = "us-west-2"
    }

    terraform {
      required_providers {
        awscc = {
          source  = "hashicorp/awscc"
          version = ">= 1.25.0"
        }
      }
    }
  EOF
}

inputs = {
  cluster_name            = "ml-hyperpod-slurm-secondary-us-west-2"
  orchestrator            = "slurm"
  execution_role_arn      = dependency.iam.outputs.hyperpod_execution_role_arn
  vpc_id                  = dependency.networking.outputs.vpc_id
  private_subnet_ids      = dependency.networking.outputs.private_subnet_ids
  efa_security_group_id   = dependency.networking.outputs.efa_security_group_id
  fsx_filesystem_id       = dependency.shared_storage.outputs.fsx_filesystem_id
  lifecycle_scripts_s3_bucket = "ml-data-replica-159553542841-us-west-2"
  instance_groups = [
    {
      instance_group_name = "controller"
      instance_type       = "ml.m5.xlarge"
      instance_count      = 1
      life_cycle_config = {
        source_s3_uri = "s3://ml-data-replica-159553542841-us-west-2/hyperpod/lifecycle-scripts/"
        on_create      = "on_create.sh"
      }
    },
    {
      instance_group_name = "gpu-workers"
      instance_type       = "ml.p5.48xlarge"
      instance_count      = 8
      life_cycle_config = {
        source_s3_uri = "s3://ml-data-replica-159553542841-us-west-2/hyperpod/lifecycle-scripts/"
        on_create      = "on_create.sh"
      }
    },
  ]
}
