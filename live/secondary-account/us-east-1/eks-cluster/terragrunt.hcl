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
  cluster_name          = "ml-training-secondary-us-east-1"
  vpc_id                = dependency.networking.outputs.vpc_id
  # Cluster was created with 2 AZs (us-east-1a/b); EKS forbids adding new AZs post-creation
  private_subnet_ids    = slice(dependency.networking.outputs.private_subnet_ids, 0, 2)
  efa_security_group_id = dependency.networking.outputs.efa_security_group_id

  # ArgoCD access — disabled until ArgoCD-Spoke-Access role is created
  argocd_access_role_arns = []

  # IAM role names — match deployed state (explicit names, no name_prefix)
  cluster_iam_role_use_name_prefix = false
  karpenter_controller_role_name   = "KarpenterController-ml-training-secondary-us-east-1"
  karpenter_node_role_name         = "KarpenterNode-ml-training-secondary-us-east-1"

  # HyperPod observability and task governance
  enable_cloudwatch_observability = true
  enable_hyperpod_task_governance = true
}
