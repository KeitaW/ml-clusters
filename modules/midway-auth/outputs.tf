output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_user_pool_domain" {
  description = "Cognito hosted UI domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "cognito_app_client_ids" {
  description = "Map of service name to Cognito App Client ID"
  value       = { for k, v in aws_cognito_user_pool_client.services : k => v.id }
}

output "acm_certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.zone_id
}

output "route53_zone_name_servers" {
  description = "Name servers for the hosted zone (if created)"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].name_servers : []
}
