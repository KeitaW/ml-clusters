terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/midway-auth"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

inputs = {
  tags = {
    Module = "midway-auth"
  }
}
