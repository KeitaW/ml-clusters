variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for server-side encryption (SSE-KMS)"
  type        = string
}

variable "replication_source_role_arns" {
  description = "IAM role ARNs allowed to replicate objects to this bucket (for destination buckets)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the S3 bucket"
  type        = map(string)
  default     = {}
}
