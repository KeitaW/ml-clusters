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

inputs = {
  cluster_name          = "ml-cluster-main-us-west-2"
  vpc_id                = dependency.networking.outputs.vpc_id
  private_subnet_ids    = dependency.networking.outputs.private_subnet_ids
  efa_security_group_id = dependency.networking.outputs.efa_security_group_id

  # ArgoCD hub access — deterministic role name avoids circular dependency
  argocd_access_role_arns = ["arn:aws:iam::483026362307:role/ArgoCD-Hub-Controller"]
}
