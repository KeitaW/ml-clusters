output "replication_configuration_id" {
  description = "The ID of the S3 bucket replication configuration"
  value       = aws_s3_bucket_replication_configuration.this.id
}
