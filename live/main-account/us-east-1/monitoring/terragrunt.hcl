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
  account_name       = "main"
  aws_region         = "us-east-1"
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids

  # Grafana disabled — IAM Identity Center is not enabled in this account.
  # Set to true and configure grafana_auth_providers after enabling SSO or SAML.
  enable_grafana = false

  # S3 replication not yet configured — alarm deferred
  # s3_replication_bucket_name      = "ml-data-central-483026362307-us-east-1"
  # s3_replication_dest_bucket_name = "ml-data-replica-..."
  # s3_replication_rule_id          = "..."
}
