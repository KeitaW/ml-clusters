# midway-auth

Route53, ACM, and Cognito with Amazon Federate (Midway) OIDC federation.

## Overview

Sets up authentication infrastructure for cluster services. Creates a Route53 hosted zone (or uses an existing one), provisions and validates an ACM certificate via DNS, and configures a Cognito User Pool federated with Amazon Federate (Midway) as an OIDC identity provider. Multiple service-specific Cognito app clients can be created for ArgoCD, Atlantis, and other services.

## Resources Created

- Route53 hosted zone (optional, can reference existing)
- ACM certificate with DNS validation and wildcard SANs
- DNS validation records and certificate validation waiter
- Cognito User Pool
- Cognito OIDC identity provider (AmazonFederate)
- Cognito hosted UI domain
- Cognito app clients (one per service in `service_configs`)

## Usage

```hcl
# live/_envcommon/midway-auth.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/midway-auth"
}

inputs = {
  domain_name                = "mlkeita.people.aws.dev"
  subject_alternative_names  = ["*.mlkeita.people.aws.dev"]
  cognito_user_pool_name     = "ml-clusters-mlkeita"
  cognito_domain_prefix      = "ml-clusters-mlkeita"
  federate_client_id         = get_env("FEDERATE_CLIENT_ID")
  federate_client_secret     = get_env("FEDERATE_CLIENT_SECRET")

  service_configs = {
    argocd = {
      callback_urls = ["https://argocd.mlkeita.people.aws.dev/oauth2/idpresponse"]
      logout_urls   = ["https://argocd.mlkeita.people.aws.dev"]
    }
    atlantis = {
      callback_urls = ["https://atlantis.mlkeita.people.aws.dev/oauth2/idpresponse"]
      logout_urls   = ["https://atlantis.mlkeita.people.aws.dev"]
    }
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `domain_name` | `string` | — | Yes | Root domain name |
| `subject_alternative_names` | `list(string)` | `[]` | No | SANs for the ACM certificate |
| `create_hosted_zone` | `bool` | `false` | No | Create a new Route53 hosted zone |
| `cognito_user_pool_name` | `string` | — | Yes | Cognito User Pool name |
| `cognito_domain_prefix` | `string` | — | Yes | Cognito hosted UI domain prefix (globally unique) |
| `federate_client_id` | `string` (sensitive) | — | Yes | OIDC client ID from Amazon Federate |
| `federate_client_secret` | `string` (sensitive) | — | Yes | OIDC client secret from Amazon Federate |
| `federate_oidc_issuer` | `string` | `"https://idp.federate.amazon.com"` | No | Federate OIDC issuer URL |
| `service_configs` | `map(object)` | `{}` | No | Service-specific Cognito app client configs |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_user_pool_arn` | Cognito User Pool ARN |
| `cognito_user_pool_domain` | Cognito hosted UI domain |
| `cognito_app_client_ids` | Map of service name to Cognito App Client ID |
| `acm_certificate_arn` | ARN of the validated ACM certificate |
| `route53_zone_id` | Route53 hosted zone ID |
| `route53_zone_name_servers` | Name servers (if zone was created) |

## Dependencies

- None — this is a standalone module consumed by argocd, atlantis, and eks-cluster
- Required providers: `hashicorp/aws ~> 6.0`
