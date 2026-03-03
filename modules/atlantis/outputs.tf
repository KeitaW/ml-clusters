output "atlantis_namespace" {
  description = "The namespace where Atlantis is deployed"
  value       = kubernetes_namespace_v1.atlantis.metadata[0].name
}

output "atlantis_release_name" {
  description = "The name of the Atlantis Helm release"
  value       = helm_release.atlantis.name
}

output "atlantis_secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret containing GitHub credentials"
  value       = aws_secretsmanager_secret.atlantis_github.arn
}

output "atlantis_webhook_secret" {
  description = "Generated webhook secret for GitHub webhook configuration"
  value       = random_password.webhook_secret.result
  sensitive   = true
}

output "atlantis_pod_identity_role_arn" {
  description = "ARN of the IAM role used by Atlantis via EKS Pod Identity"
  value       = aws_iam_role.atlantis_pod_identity.arn
}
