include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/eks-cluster.hcl"
  expose = true
}

dependency "networking" {
  config_path = "../networking"
}

dependency "iam" {
  config_path = "../iam"
}

dependency "midway_auth" {
  config_path = "../midway-auth"
}

dependency "monitoring" {
  config_path = "../monitoring"
}

inputs = {
  cluster_name          = "ml-cluster-main-us-east-1"
  vpc_id                = dependency.networking.outputs.vpc_id
  private_subnet_ids    = dependency.networking.outputs.private_subnet_ids
  efa_security_group_id = dependency.networking.outputs.efa_security_group_id
  route53_zone_id       = dependency.midway_auth.outputs.route53_zone_id
  amp_workspace_arn     = dependency.monitoring.outputs.amp_workspace_arn
}
