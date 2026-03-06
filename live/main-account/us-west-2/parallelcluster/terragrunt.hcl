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

dependency "shared_storage" {
  config_path = "../shared-storage"
}

# Generate parallelcluster provider — Atlantis (TerraformExecutionRole) calls the API
generate "pcluster_provider" {
  path      = "pcluster_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws-parallelcluster" {
      region         = "us-west-2"
      api_stack_name = "pcluster-api-us-west-2"
      role_arn       = "arn:aws:iam::483026362307:role/TerraformExecutionRole"
    }
  EOF
}

inputs = {
  region              = "us-west-2"
  deploy_pcluster_api = true
  api_stack_name      = "pcluster-api-us-west-2"
  api_version         = "3.13.1"

  api_parameters = {
    EnableIamAdminAccess = "true"
  }

  cluster_configs = {
    e2e-pr1003 = {
      config_path             = "${get_repo_root()}/cluster-configs/parallelcluster/e2e-pr1003.yaml"
      head_node_subnet_id     = dependency.networking.outputs.public_subnet_ids[2]
      compute_subnet_id       = dependency.networking.outputs.private_subnet_ids[2]
      fsx_filesystem_id       = dependency.shared_storage.outputs.fsx_filesystem_id
      efs_filesystem_id       = dependency.shared_storage.outputs.efs_filesystem_id
      capacity_reservation_id = "cr-0705ae6662a9c460a"
    }
  }
}
