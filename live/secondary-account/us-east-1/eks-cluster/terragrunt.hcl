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

  mock_outputs = {
    argocd_spoke_access_role_arn = "arn:aws:iam::159553542841:role/mock"
  }
  mock_outputs_allowed_terraform_commands      = ["validate", "plan"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "s3_replica" {
  config_path = "../s3-data-replica"

  mock_outputs = {
    bucket_arn = "arn:aws:s3:::mock-bucket"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "monitoring" {
  config_path = "../monitoring"

  mock_outputs = {
    amp_workspace_arn = "arn:aws:aps:us-east-1:159553542841:workspace/ws-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  cluster_name          = "ml-training-secondary-us-east-1"
  vpc_id                = dependency.networking.outputs.vpc_id
  # Cluster was created with 2 AZs (us-east-1a/b); EKS forbids adding new AZs post-creation
  private_subnet_ids    = slice(dependency.networking.outputs.private_subnet_ids, 0, 2)
  efa_security_group_id = dependency.networking.outputs.efa_security_group_id

  # ArgoCD access — cross-account spoke role for hub management
  argocd_access_role_arns = [dependency.iam.outputs.argocd_spoke_access_role_arn]

  # IAM role names — match deployed state (explicit names, no name_prefix)
  cluster_iam_role_use_name_prefix = false
  karpenter_controller_role_name   = "KarpenterController-ml-training-secondary-us-east-1"
  karpenter_node_role_name         = "KarpenterNode-ml-training-secondary-us-east-1"

  # ADOT collector IRSA role for Prometheus remote write
  amp_workspace_arn = dependency.monitoring.outputs.amp_workspace_arn

  # Ray cluster IRSA — S3 access for checkpoints and data
  ray_s3_bucket_arns = [dependency.s3_replica.outputs.bucket_arn]

  # HyperPod observability and task governance
  enable_cloudwatch_observability = true
  enable_hyperpod_task_governance = true
}
