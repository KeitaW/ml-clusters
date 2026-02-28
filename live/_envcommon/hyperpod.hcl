terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/hyperpod"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

inputs = {
  aws_region = local.region_vars.locals.aws_region
}
