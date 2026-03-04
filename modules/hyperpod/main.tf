###############################################################################
# Locals
###############################################################################

locals {
  is_eks                = var.orchestrator == "eks"
  is_slurm              = var.orchestrator == "slurm"
  lifecycle_scripts_dir = "${path.module}/${var.lifecycle_scripts_path}/base-config"
}

###############################################################################
# CloudWatch Log Group
###############################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  count = var.create_cloudwatch_log_group ? 1 : 0

  name              = "/aws/sagemaker/Clusters/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

###############################################################################
# Lifecycle Scripts - Upload to S3
###############################################################################

resource "aws_s3_object" "lifecycle_scripts" {
  for_each = var.lifecycle_scripts_s3_bucket != "" ? fileset(local.lifecycle_scripts_dir, "**") : toset([])

  bucket = var.lifecycle_scripts_s3_bucket
  key    = "${var.lifecycle_scripts_s3_prefix}/${each.value}"
  source = "${local.lifecycle_scripts_dir}/${each.value}"
  etag   = filemd5("${local.lifecycle_scripts_dir}/${each.value}")
}

###############################################################################
# Slurm Provisioning Parameters
###############################################################################

resource "aws_s3_object" "provisioning_parameters" {
  count = var.lifecycle_scripts_s3_bucket != "" && var.slurm_provisioning_parameters != null ? 1 : 0

  bucket       = var.lifecycle_scripts_s3_bucket
  key          = "${var.lifecycle_scripts_s3_prefix}/provisioning_parameters.json"
  content_type = "application/json"
  content = jsonencode({
    version          = "1.0"
    workload_manager = "slurm"
    controller_group = var.slurm_provisioning_parameters.controller_group
    worker_groups = [for wg in var.slurm_provisioning_parameters.worker_groups : {
      instance_group_name = wg.instance_group_name
      partition_name      = coalesce(wg.partition_name, wg.instance_group_name)
    }]
    fsx_dns_name   = var.slurm_provisioning_parameters.fsx_dns_name
    fsx_mount_name = var.slurm_provisioning_parameters.fsx_mount_name
  })
}

###############################################################################
# SageMaker HyperPod Cluster
###############################################################################

resource "awscc_sagemaker_cluster" "this" {
  cluster_name = var.cluster_name

  # Orchestrator: EKS or Slurm (null = Slurm default)
  orchestrator = local.is_eks ? {
    eks = {
      cluster_arn = var.eks_cluster_arn
    }
  } : null

  # Instance groups
  instance_groups = [for ig in var.instance_groups : merge(
    {
      instance_group_name = ig.instance_group_name
      instance_type       = ig.instance_type
      instance_count      = ig.instance_count
      execution_role      = coalesce(ig.execution_role_arn, var.execution_role_arn)
      life_cycle_config = {
        source_s3_uri = ig.life_cycle_config.source_s3_uri
        on_create     = ig.life_cycle_config.on_create
      }
    },
    # Optional: min instance count
    ig.min_instance_count != null ? {
      min_instance_count = ig.min_instance_count
    } : {},
    # Optional: threads per core
    ig.threads_per_core != null ? {
      threads_per_core = ig.threads_per_core
    } : {},
    # Optional: training plan
    ig.training_plan_arn != null ? {
      training_plan_arn = ig.training_plan_arn
    } : {},
    # Optional: EBS storage
    ig.ebs_volume_size_gb != null ? {
      instance_storage_configs = [
        {
          ebs_volume_config = merge(
            { volume_size_in_gb = ig.ebs_volume_size_gb },
            ig.ebs_volume_kms_key != null ? { volume_kms_key_id = ig.ebs_volume_kms_key } : {}
          )
        }
      ]
    } : {},
    # Optional: deep health checks
    length(ig.on_start_deep_health_checks) > 0 ? {
      on_start_deep_health_checks = ig.on_start_deep_health_checks
    } : {},
    # Optional: per-group VPC override (multi-AZ)
    ig.override_vpc_config != null ? {
      override_vpc_config = {
        subnets            = ig.override_vpc_config.subnet_ids
        security_group_ids = ig.override_vpc_config.security_group_ids
      }
    } : {},
    # Optional: Kubernetes config (EKS only)
    local.is_eks && ig.kubernetes_config != null ? {
      kubernetes_config = merge(
        length(ig.kubernetes_config.labels) > 0 ? {
          labels = ig.kubernetes_config.labels
        } : {},
        length(ig.kubernetes_config.taints) > 0 ? {
          taints = [for t in ig.kubernetes_config.taints : {
            key    = t.key
            value  = t.value
            effect = t.effect
          }]
        } : {}
      )
    } : {},
  )]

  node_recovery = var.node_recovery

  # VPC configuration
  vpc_config = {
    security_group_ids = [var.efa_security_group_id]
    subnets            = var.private_subnet_ids
  }

  # EKS autoscaling (Karpenter)
  auto_scaling = var.enable_eks_autoscaling ? {
    mode             = "Enable"
    auto_scaler_type = "Karpenter"
  } : null

  cluster_role = var.enable_eks_autoscaling ? var.eks_autoscaling_role_arn : null

  node_provisioning_mode = var.enable_eks_autoscaling ? "Continuous" : null

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
      condition     = !var.enable_eks_autoscaling || local.is_eks
      error_message = "enable_eks_autoscaling requires orchestrator to be 'eks'"
    }

    precondition {
      condition     = !var.enable_eks_autoscaling || var.eks_autoscaling_role_arn != ""
      error_message = "eks_autoscaling_role_arn is required when enable_eks_autoscaling is true"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_s3_object.lifecycle_scripts,
    aws_s3_object.provisioning_parameters,
  ]
}
