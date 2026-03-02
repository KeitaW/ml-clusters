include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/argocd"
}

dependency "eks" {
  config_path = "../eks-training"
}

dependency "midway_auth" {
  config_path = "../midway-auth"
}

inputs = {
  cluster_name               = dependency.eks.outputs.cluster_name
  cluster_endpoint           = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate     = dependency.eks.outputs.cluster_certificate_authority_data
  assume_role_arn            = "arn:aws:iam::483026362307:role/TerraformExecutionRole"
  spoke_clusters             = {}

  # Midway authentication
  enable_cognito_auth    = true
  acm_certificate_arn    = dependency.midway_auth.outputs.acm_certificate_arn
  argocd_hostname        = "argocd.mlkeita.people.aws.dev"
  alb_ingress_group_name = "ml-cluster-services"
  cognito_user_pool_arn  = dependency.midway_auth.outputs.cognito_user_pool_arn
  cognito_app_client_id  = dependency.midway_auth.outputs.cognito_app_client_ids["argocd"]
  cognito_user_pool_domain = dependency.midway_auth.outputs.cognito_user_pool_domain
}
