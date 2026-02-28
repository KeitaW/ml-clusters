output "kms_key_arn" {
  description = "ARN of the shared KMS key"
  value       = aws_kms_key.shared.arn
}

output "kms_key_id" {
  description = "ID of the shared KMS key"
  value       = aws_kms_key.shared.key_id
}

output "terraform_execution_role_arn" {
  description = "ARN of the TerraformExecutionRole"
  value       = try(aws_iam_role.terraform_execution[0].arn, null)
}

output "parallelcluster_head_node_role_arn" {
  description = "ARN of the ParallelCluster head node role"
  value       = try(aws_iam_role.parallelcluster_head_node[0].arn, null)
}

output "parallelcluster_compute_role_arn" {
  description = "ARN of the ParallelCluster compute role"
  value       = try(aws_iam_role.parallelcluster_compute[0].arn, null)
}

output "hyperpod_execution_role_arn" {
  description = "ARN of the HyperPod execution role"
  value       = try(aws_iam_role.hyperpod_execution[0].arn, null)
}

output "s3_replication_role_arn" {
  description = "ARN of the S3 replication role"
  value       = try(aws_iam_role.s3_replication[0].arn, null)
}
