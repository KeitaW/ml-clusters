# Precondition: EKS cluster ARN required when orchestrator is "eks"
locals {
  is_eks = var.orchestrator == "eks"
}

# Upload lifecycle scripts to S3
resource "aws_s3_object" "lifecycle_scripts" {
  for_each = var.lifecycle_scripts_s3_bucket != "" ? fileset("${path.module}/../../cluster-configs/hyperpod/lifecycle-scripts/base-config/", "*") : toset([])

  bucket = var.lifecycle_scripts_s3_bucket
  key    = "hyperpod/lifecycle-scripts/${each.value}"
  source = "${path.module}/../../cluster-configs/hyperpod/lifecycle-scripts/base-config/${each.value}"
  etag   = filemd5("${path.module}/../../cluster-configs/hyperpod/lifecycle-scripts/base-config/${each.value}")
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
  }
}
