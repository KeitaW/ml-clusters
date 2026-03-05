include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/osmo-data"
}

dependency "networking" {
  config_path = "../networking"
}

dependency "iam" {
  config_path = "../iam"
}

dependency "osmo_eks" {
  config_path = "../osmo-eks"

  mock_outputs = {
    node_security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vpc_id                     = dependency.networking.outputs.vpc_id
  private_subnet_ids         = dependency.networking.outputs.private_subnet_ids
  kms_key_arn                = dependency.iam.outputs.kms_key_arn
  eks_node_security_group_id = dependency.osmo_eks.outputs.node_security_group_id

  db_name            = "osmo"
  db_master_username = "osmo_admin"
  db_min_capacity    = 0.5
  db_max_capacity    = 4
}
