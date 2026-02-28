locals {
  api_stack_name = var.api_stack_name != "" ? var.api_stack_name : "pcluster-api-${var.region}"
}

module "pcluster" {
  source  = "aws-tf/parallelcluster/aws"
  version = "~> 1.1"

  region              = var.region
  api_stack_name      = local.api_stack_name
  api_version         = var.api_version
  deploy_pcluster_api = var.deploy_pcluster_api

  cluster_configs = { for name, config in var.cluster_configs : name => {
    configuration = templatefile(config.config_path, {
      head_node_subnet_id     = config.head_node_subnet_id
      compute_subnet_id       = config.compute_subnet_id
      fsx_filesystem_id       = config.fsx_filesystem_id
      efs_filesystem_id       = config.efs_filesystem_id
      capacity_reservation_id = config.capacity_reservation_id
    })
  } }
}
