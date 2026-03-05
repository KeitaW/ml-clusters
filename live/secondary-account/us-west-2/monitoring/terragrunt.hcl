include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/monitoring"
}

dependency "networking" {
  config_path = "../networking"
}

inputs = {
  account_name       = "secondary"
  aws_region         = "us-west-2"
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids

  # Share us-east-1 Grafana workspace later via cross-region AMP data source
  enable_grafana = false
}
