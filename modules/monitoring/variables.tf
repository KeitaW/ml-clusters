variable "account_name" {
  description = "Name of the AWS account (used in resource naming)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the monitoring resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to monitor"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs to monitor for IP exhaustion"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster to monitor"
  type        = string
  default     = ""
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all monitoring resources"
  type        = map(string)
  default     = {}
}
