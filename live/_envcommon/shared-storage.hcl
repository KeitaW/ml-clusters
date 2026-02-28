terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/shared-storage"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

inputs = {
  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
}
