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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
