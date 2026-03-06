output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster auth"
  value       = module.eks.cluster_certificate_authority_data
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "sdg_output_bucket" {
  description = "S3 bucket for SDG output data"
  value       = aws_s3_bucket.sdg_output.id
}

output "karpenter_node_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes"
  value       = module.eks.karpenter_node_iam_role_name
}
