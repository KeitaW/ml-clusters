variable "account_name" {
  description = "Name of the AWS account, used for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where storage resources will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for mount targets and filesystem placement"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption of EFS and FSx filesystems"
  type        = string
}

variable "s3_data_bucket_arn" {
  description = "S3 bucket ARN for FSx Data Repository Association"
  type        = string
}

variable "fsx_storage_capacity" {
  description = "Storage capacity for FSx Lustre filesystem in GiB. Must be a multiple of 2400"
  type        = number
  default     = 4800
}

variable "fsx_throughput_per_unit" {
  description = "Throughput per unit of storage in MB/s per TiB. Valid values: 125, 250, 500, 1000"
  type        = number
  default     = 500
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
