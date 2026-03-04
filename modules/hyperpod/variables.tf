variable "cluster_name" {
  description = "Name of the HyperPod cluster"
  type        = string
}

variable "orchestrator" {
  description = "Orchestrator type: 'slurm' or 'eks'"
  type        = string
  default     = "slurm"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM execution role ARN for the cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "efa_security_group_id" {
  description = "Security group ID for EFA traffic"
  type        = string
}

variable "fsx_filesystem_id" {
  description = "FSx filesystem ID"
  type        = string
  default     = ""
}

variable "lifecycle_scripts_s3_bucket" {
  description = "S3 bucket for lifecycle scripts"
  type        = string
  default     = ""
}

variable "instance_groups" {
  description = "List of instance group configurations"
  type = list(object({
    instance_group_name = string
    instance_type       = string
    instance_count      = number
    life_cycle_config = object({
      source_s3_uri = string
      on_create     = string
    })
  }))
}

variable "eks_cluster_arn" {
  description = "EKS cluster ARN, required when orchestrator is 'eks'"
  type        = string
  default     = ""
}

variable "auto_scaling_enabled" {
  description = "Enable Karpenter-based autoscaling for EKS-orchestrated HyperPod"
  type        = bool
  default     = false
}

variable "cluster_role_arn" {
  description = "IAM role ARN for HyperPod cluster-level operations (Karpenter autoscaling). Required when auto_scaling_enabled=true."
  type        = string
  default     = ""
}

variable "node_provisioning_mode" {
  description = "Node provisioning mode: 'Continuous' for dynamic provisioning, null for standard"
  type        = string
  default     = null
}

variable "lifecycle_scripts_local_path" {
  description = "Local path to lifecycle scripts directory. Defaults to module's embedded base-config scripts."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
