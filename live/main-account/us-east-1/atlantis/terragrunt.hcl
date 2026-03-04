include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/atlantis"
}

dependency "eks" {
  config_path = "../eks-cluster"
}

dependency "iam" {
  config_path = "../iam"
}

dependency "midway_auth" {
  config_path = "../midway-auth"
}

inputs = {
  cluster_name                  = dependency.eks.outputs.cluster_name
  cluster_endpoint              = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate        = dependency.eks.outputs.cluster_certificate_authority_data
  assume_role_arn               = "arn:aws:iam::483026362307:role/TerraformExecutionRole"
  terraform_execution_role_arns = [
    "arn:aws:iam::483026362307:role/TerraformExecutionRole",
    "arn:aws:iam::159553542841:role/TerraformExecutionRole",
  ]
  tfstate_bucket_name           = "ml-clusters-tfstate-483026362307"
  kms_key_arn                   = dependency.iam.outputs.kms_key_arn
  github_user                   = "KeitaW"
  github_token                  = get_env("GITHUB_PERSONAL_ACCESS_TOKEN", "")

  # Midway authentication
  enable_cognito_auth      = true
  acm_certificate_arn      = dependency.midway_auth.outputs.acm_certificate_arn
  atlantis_hostname        = "atlantis.mlkeita.people.aws.dev"
  alb_ingress_group_name   = "ml-cluster-services"
  cognito_user_pool_arn    = dependency.midway_auth.outputs.cognito_user_pool_arn
  cognito_app_client_id    = dependency.midway_auth.outputs.cognito_app_client_ids["atlantis"]
  cognito_user_pool_domain = dependency.midway_auth.outputs.cognito_user_pool_domain
}
