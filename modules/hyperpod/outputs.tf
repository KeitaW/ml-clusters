output "cluster_arn" {
  description = "ARN of the HyperPod cluster"
  value       = awscc_sagemaker_cluster.this.cluster_arn
}

output "cluster_name" {
  description = "Name of the HyperPod cluster"
  value       = var.cluster_name
}
