terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/networking"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

inputs = {
  account_name         = local.account_vars.locals.account_name
  aws_region           = local.region_vars.locals.aws_region
  vpc_cidr             = local.region_vars.locals.vpc_cidr
  availability_zones   = local.region_vars.locals.availability_zones
  private_subnet_cidrs = local.region_vars.locals.private_subnet_cidrs
  public_subnet_cidrs  = local.region_vars.locals.public_subnet_cidrs
}
