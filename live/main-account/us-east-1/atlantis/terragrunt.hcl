include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/atlantis"
}

dependency "eks" {
  config_path = "../eks-training"
}

dependency "iam" {
  config_path = "../iam"
}

inputs = {
  cluster_name           = dependency.eks.outputs.cluster_name
  cluster_endpoint       = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.eks.outputs.cluster_certificate_authority_data
  assume_role_arn        = "arn:aws:iam::483026362307:role/TerraformExecutionRole"
  kms_key_arn            = dependency.iam.outputs.kms_key_arn
  github_user            = "KeitaW"
  # github_token: set via TF_VAR_github_token environment variable at apply time
}
