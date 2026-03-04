###############################################################################
# Core
###############################################################################

variable "cluster_name" {
  description = "Name of the HyperPod cluster (1-63 chars)"
  type        = string

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 63
    error_message = "cluster_name must be between 1 and 63 characters"
  }
}

variable "orchestrator" {
  description = "Orchestrator type: 'slurm' or 'eks'"
  type        = string
  default     = "slurm"

  validation {
    condition     = contains(["slurm", "eks"], var.orchestrator)
    error_message = "orchestrator must be 'slurm' or 'eks'"
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "node_recovery" {
  description = "Node recovery mode: 'Automatic' or 'None'"
  type        = string
  default     = "Automatic"

  validation {
    condition     = contains(["Automatic", "None"], var.node_recovery)
    error_message = "node_recovery must be 'Automatic' or 'None'"
  }
}

###############################################################################
# IAM
###############################################################################

variable "execution_role_arn" {
  description = "Default IAM execution role ARN for instance groups (can be overridden per group)"
  type        = string
}

###############################################################################
# Networking
###############################################################################

variable "vpc_id" {
  description = "VPC ID for the cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the cluster VPC config"
  type        = list(string)
}

variable "efa_security_group_id" {
  description = "Security group ID for EFA traffic (self-referencing)"
  type        = string
}

###############################################################################
# Instance Groups
###############################################################################

variable "instance_groups" {
  description = "List of instance group configurations"
  type = list(object({
    instance_group_name = string
    instance_type       = string
    instance_count      = number
    min_instance_count  = optional(number)
    execution_role_arn  = optional(string) # Override default execution_role_arn
    threads_per_core    = optional(number)
    training_plan_arn   = optional(string)

    life_cycle_config = object({
      source_s3_uri = string
      on_create     = string
    })

    # EBS storage (mounted at /opt/sagemaker)
    ebs_volume_size_gb = optional(number)
    ebs_volume_kms_key = optional(string)

    # Deep health checks for GPU/accelerator validation
    on_start_deep_health_checks = optional(list(string), [])

    # Per-group VPC override (multi-AZ support)
    override_vpc_config = optional(object({
      subnet_ids         = list(string)
      security_group_ids = list(string)
    }))

    # Kubernetes config (EKS orchestrator only)
    kubernetes_config = optional(object({
      labels = optional(map(string), {})
      taints = optional(list(object({
        key    = string
        value  = string
        effect = string
      })), [])
    }))
  }))
}

###############################################################################
# EKS Orchestration
###############################################################################

variable "eks_cluster_arn" {
  description = "EKS cluster ARN, required when orchestrator is 'eks'"
  type        = string
  default     = ""
}

variable "enable_eks_autoscaling" {
  description = "Enable Karpenter-based autoscaling (EKS only)"
  type        = bool
  default     = false
}

variable "eks_autoscaling_role_arn" {
  description = "IAM role ARN for Karpenter autoscaling operations (EKS only)"
  type        = string
  default     = ""
}

###############################################################################
# Slurm Orchestration - Lifecycle Scripts
###############################################################################

variable "lifecycle_scripts_s3_bucket" {
  description = "S3 bucket name for lifecycle scripts upload (should match sagemaker-* pattern)"
  type        = string
  default     = ""
}

variable "lifecycle_scripts_s3_prefix" {
  description = "S3 key prefix for lifecycle scripts"
  type        = string
  default     = "hyperpod/lifecycle-scripts"
}

variable "lifecycle_scripts_path" {
  description = "Local path to lifecycle scripts directory (relative to module root)"
  type        = string
  default     = "../../cluster-configs/hyperpod/lifecycle-scripts"
}

###############################################################################
# Slurm Provisioning Parameters
###############################################################################

variable "slurm_provisioning_parameters" {
  description = "Slurm provisioning parameters for lifecycle scripts (rendered to provisioning_parameters.json)"
  type = object({
    controller_group = string
    worker_groups = list(object({
      instance_group_name = string
      partition_name      = optional(string)
    }))
    fsx_dns_name   = optional(string, "")
    fsx_mount_name = optional(string, "")
  })
  default = null
}

###############################################################################
# Shared Storage
###############################################################################

variable "fsx_filesystem_id" {
  description = "FSx for Lustre filesystem ID (for lifecycle script configuration)"
  type        = string
  default     = ""
}

###############################################################################
# Observability
###############################################################################

variable "create_cloudwatch_log_group" {
  description = "Create CloudWatch log group for cluster logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
