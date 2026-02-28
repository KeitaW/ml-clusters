include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/monitoring"
}

dependency "networking" {
  config_path = "../networking"
}

dependency "eks" {
  config_path = "../eks-training"
}

inputs = {
  account_name = "main"
  aws_region   = "us-east-1"
  vpc_id       = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids
  eks_cluster_name   = dependency.eks.outputs.cluster_name
}
