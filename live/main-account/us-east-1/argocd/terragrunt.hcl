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
  spoke_clusters             = {}
}
