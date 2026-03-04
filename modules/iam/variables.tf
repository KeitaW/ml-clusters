variable "account_name" {
  description = "Name of the AWS account, used in resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource naming"
  type        = string
}

variable "cross_account_ids" {
  description = "Account IDs for cross-account KMS access"
  type        = list(string)
  default     = []
}

variable "create_terraform_execution_role" {
  description = "Whether to create the TerraformExecutionRole"
  type        = bool
  default     = true
}

variable "terraform_execution_trust_account_ids" {
  description = "Account IDs allowed to assume TerraformExecutionRole. Defaults to the current account if empty."
  type        = list(string)
  default     = []
}

variable "create_parallelcluster_roles" {
  description = "Whether to create ParallelCluster head node and compute IAM roles"
  type        = bool
  default     = false
}

variable "create_hyperpod_role" {
  description = "Whether to create the HyperPod execution role"
  type        = bool
  default     = false
}

variable "create_hyperpod_karpenter_role" {
  description = "Whether to create the HyperPod Karpenter autoscaling role"
  type        = bool
  default     = false
}

variable "create_s3_replication_role" {
  description = "Whether to create the S3 replication role"
  type        = bool
  default     = false
}

variable "s3_source_bucket_arn" {
  description = "ARN of the source S3 bucket for replication role"
  type        = string
  default     = ""
}

variable "s3_destination_bucket_arns" {
  description = "ARNs of the destination S3 buckets for replication role"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "Destination KMS key ARNs for S3 replication encryption"
  type        = list(string)
  default     = []
}

variable "create_argocd_spoke_role" {
  description = "Whether to create the ArgoCD-Spoke-Access IAM role for cross-account hub access"
  type        = bool
  default     = false
}

variable "argocd_hub_role_arn" {
  description = "ARN of the ArgoCD hub controller IRSA role that can assume the spoke access role"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
