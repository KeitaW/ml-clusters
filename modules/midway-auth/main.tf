################################################################################
# Route53 Hosted Zone
################################################################################

data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : 1
  name  = var.domain_name
}

resource "aws_route53_zone" "main" {
  count = var.create_hosted_zone ? 1 : 0
  name  = var.domain_name
  tags  = var.tags
}

locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

################################################################################
# ACM Certificate
################################################################################

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

################################################################################
# Cognito User Pool
################################################################################

resource "aws_cognito_user_pool" "main" {
  name = var.cognito_user_pool_name
  tags = var.tags
}

################################################################################
# Cognito OIDC Identity Provider (Amazon Federate / Midway)
################################################################################

resource "aws_cognito_identity_provider" "federate" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "AmazonFederate"
  provider_type = "OIDC"

  provider_details = {
    client_id                 = var.federate_client_id
    client_secret             = var.federate_client_secret
    oidc_issuer               = var.federate_oidc_issuer
    attributes_request_method = "GET"
    authorize_scopes          = "openid"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

################################################################################
# Cognito User Pool Domain (Hosted UI)
################################################################################

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

################################################################################
# Cognito App Clients (one per service)
################################################################################

resource "aws_cognito_user_pool_client" "services" {
  for_each = var.service_configs

  name                                 = each.key
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = each.value.callback_urls
  logout_urls                          = each.value.logout_urls
  supported_identity_providers         = ["AmazonFederate"]

  depends_on = [aws_cognito_identity_provider.federate]
}
