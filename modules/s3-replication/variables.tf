variable "source_bucket_id" {
  description = "ID (name) of the source S3 bucket for replication"
  type        = string
}

variable "iam_role_arn" {
  description = "ARN of the IAM role used for S3 replication"
  type        = string
}

variable "replication_rules" {
  description = "List of replication rules to configure"
  type = list(object({
    id                      = string
    prefix                  = string
    destination_bucket_arn  = string
    destination_account_id  = string
    destination_kms_key_arn = string
    storage_class           = optional(string, "STANDARD")
  }))
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
