# Precondition: EKS cluster ARN required when orchestrator is "eks"
locals {
  is_eks                = var.orchestrator == "eks"
  lifecycle_scripts_dir = var.lifecycle_scripts_local_path != "" ? var.lifecycle_scripts_local_path : "${path.module}/lifecycle-scripts"
}

# Upload lifecycle scripts to S3
resource "aws_s3_object" "lifecycle_scripts" {
  for_each = var.lifecycle_scripts_s3_bucket != "" ? fileset(local.lifecycle_scripts_dir, "*") : toset([])

  bucket = var.lifecycle_scripts_s3_bucket
  key    = "hyperpod/lifecycle-scripts/${each.value}"
  source = "${local.lifecycle_scripts_dir}/${each.value}"
  etag   = filemd5("${local.lifecycle_scripts_dir}/${each.value}")
}

resource "awscc_sagemaker_cluster" "this" {
  cluster_name = var.cluster_name

  orchestrator = local.is_eks ? {
    eks = {
      cluster_arn = var.eks_cluster_arn
    }
  } : null

  instance_groups = [for ig in var.instance_groups : {
    instance_group_name = ig.instance_group_name
    instance_type       = ig.instance_type
    instance_count      = ig.instance_count
    execution_role      = var.execution_role_arn
    life_cycle_config = {
      source_s3_uri = ig.life_cycle_config.source_s3_uri
      on_create     = ig.life_cycle_config.on_create
    }
  }]

  # Karpenter autoscaling (EKS only)
  auto_scaling = var.auto_scaling_enabled ? {
    mode             = "Enable"
    auto_scaler_type = "Karpenter"
  } : null

  cluster_role = var.auto_scaling_enabled ? var.cluster_role_arn : null

  node_provisioning_mode = var.node_provisioning_mode

  node_recovery = "Automatic"

  vpc_config = {
    security_group_ids = [var.efa_security_group_id]
    subnets            = var.private_subnet_ids
  }

  tags = [for k, v in var.tags : {
    key   = k
    value = v
  }]

  lifecycle {
    precondition {
      condition     = !local.is_eks || var.eks_cluster_arn != ""
      error_message = "eks_cluster_arn is required when orchestrator is 'eks'"
    }
    precondition {
      condition     = !var.auto_scaling_enabled || var.cluster_role_arn != ""
      error_message = "cluster_role_arn is required when auto_scaling_enabled is true"
    }
  }
}
