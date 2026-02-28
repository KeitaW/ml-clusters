include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/argocd"
}

dependency "eks" {
  config_path = "../eks-training"
}

inputs = {
  cluster_name               = dependency.eks.outputs.cluster_name
  cluster_endpoint           = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate     = dependency.eks.outputs.cluster_certificate_authority_data
  assume_role_arn            = "arn:aws:iam::483026362307:role/TerraformExecutionRole"
  spoke_clusters             = {}
}
