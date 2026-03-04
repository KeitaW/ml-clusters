variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the cluster"
  type        = list(string)
}

variable "efa_security_group_id" {
  description = "EFA security group ID"
  type        = string
  default     = ""
}

variable "authentication_mode" {
  description = "EKS authentication mode (HyperPod EKS requirement)"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for External-DNS IAM policy scoping. Leave empty to skip External-DNS IRSA."
  type        = string
  default     = ""
}

variable "amp_workspace_arn" {
  description = "ARN of the AMP workspace for ADOT IRSA. Leave empty to skip ADOT IRSA creation."
  type        = string
  default     = ""
}

variable "argocd_access_role_arns" {
  description = "IAM role ARNs to grant cluster-admin access for ArgoCD hub"
  type        = list(string)
  default     = []
}

variable "cluster_iam_role_use_name_prefix" {
  description = "Use name_prefix for the cluster-level IAM role. Set false for clusters deployed with explicit role names (e.g. long cluster names exceeding 38-char prefix limit)."
  type        = bool
  default     = true
}

variable "karpenter_controller_role_name" {
  description = "Override Karpenter controller IAM role/policy name. Empty uses module default (KarpenterController)."
  type        = string
  default     = ""
}

variable "karpenter_node_role_name" {
  description = "Override Karpenter node IAM role name. Empty uses module default (Karpenter-{cluster_name})."
  type        = string
  default     = ""
}

variable "enable_cloudwatch_observability" {
  description = "Install amazon-cloudwatch-observability EKS add-on for HyperPod dashboard"
  type        = bool
  default     = false
}

variable "enable_hyperpod_task_governance" {
  description = "Install amazon-sagemaker-hyperpod-taskgovernance EKS add-on (Kueue)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
