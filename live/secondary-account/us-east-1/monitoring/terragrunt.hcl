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
  aws_region         = "us-east-1"
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids

  # Grafana enabled — IAM Identity Center is in ap-northeast-1 (AMG supports cross-region SSO)
  enable_grafana = true

  # Admin association deferred — SSO user must be assigned to this Grafana workspace's
  # SSO application in IAM Identity Center before role association can be created.
  # grafana_admin_user_ids = ["67146a88-1001-702c-39d7-196888d63d16"]
}
