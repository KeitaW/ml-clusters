variable "name_prefix" {
  description = "Prefix for all resource names (cluster identifier, SGs, subnet group, etc.)"
  type        = string
  default     = "osmo-data"
}

variable "vpc_id" {
  description = "VPC ID where data services are deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for RDS and ElastiCache"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "EKS node security group ID (allowed to connect to RDS and Redis)"
  type        = string
}

variable "db_name" {
  description = "Name of the PostgreSQL database to create"
  type        = string
  default     = "osmo"
}

variable "db_master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "osmo_admin"
}

variable "db_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACU)"
  type        = number
  default     = 0.5
}

variable "db_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACU)"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
