output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "cluster_security_group_id" {
  description = "The security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "The security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}

output "karpenter_node_role_arn" {
  description = "The ARN of the Karpenter node IAM role"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_queue_name" {
  description = "The name of the Karpenter SQS queue for interruption handling"
  value       = module.karpenter.queue_name
}

output "karpenter_instance_profile_name" {
  description = "The name of the Karpenter instance profile"
  value       = module.karpenter.instance_profile_name != null ? module.karpenter.instance_profile_name : ""
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for the EBS CSI driver"
  value       = aws_iam_role.ebs_csi.arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for External-DNS"
  value       = var.route53_zone_id != "" ? aws_iam_role.external_dns[0].arn : ""
}

output "adot_role_arn" {
  description = "IAM role ARN for the ADOT Collector"
  value       = var.amp_workspace_arn != "" ? aws_iam_role.adot[0].arn : ""
}

output "aws_region" {
  description = "AWS region of the cluster"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID of the cluster"
  value       = var.vpc_id
}

output "oidc_provider" {
  description = "OIDC provider URL for the EKS cluster"
  value       = module.eks.oidc_provider
}
