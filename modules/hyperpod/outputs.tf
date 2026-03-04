output "cluster_arn" {
  description = "ARN of the HyperPod cluster"
  value       = awscc_sagemaker_cluster.this.cluster_arn
}

output "cluster_name" {
  description = "Name of the HyperPod cluster"
  value       = var.cluster_name
}

output "cluster_status" {
  description = "Status of the HyperPod cluster"
  value       = awscc_sagemaker_cluster.this.cluster_status
}

output "orchestrator" {
  description = "Orchestrator type (slurm or eks)"
  value       = var.orchestrator
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for cluster logs"
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.cluster[0].name : null
}

output "lifecycle_scripts_s3_uri" {
  description = "S3 URI where lifecycle scripts are stored"
  value       = var.lifecycle_scripts_s3_bucket != "" ? "s3://${var.lifecycle_scripts_s3_bucket}/${var.lifecycle_scripts_s3_prefix}" : null
}
