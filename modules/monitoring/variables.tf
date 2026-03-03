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

variable "notification_email" {
  description = "Email address for alarm notifications via SNS"
  type        = string
  default     = ""
}

variable "enable_grafana" {
  description = "Whether to create the Amazon Managed Grafana workspace. Requires IAM Identity Center or SAML IdP."
  type        = bool
  default     = false
}

variable "grafana_auth_providers" {
  description = "Authentication providers for AMG. Use [\"AWS_SSO\"] if Identity Center is enabled, or [\"SAML\"] for SAML IdP."
  type        = list(string)
  default     = ["AWS_SSO"]
}

variable "s3_replication_bucket_name" {
  description = "Source S3 bucket name for replication lag alarm. Leave empty to skip this alarm."
  type        = string
  default     = ""
}

variable "s3_replication_dest_bucket_name" {
  description = "Destination S3 bucket name for replication lag alarm."
  type        = string
  default     = ""
}

variable "s3_replication_rule_id" {
  description = "S3 replication rule ID for the replication lag alarm."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all monitoring resources"
  type        = map(string)
  default     = {}
}
