variable "domain_name" {
  description = "Root domain name (e.g., mlkeita.people.aws.dev)"
  type        = string
}

variable "subject_alternative_names" {
  description = "Subject Alternative Names for the ACM certificate (e.g., [\"*.mlkeita.people.aws.dev\"])"
  type        = list(string)
  default     = []
}

variable "create_hosted_zone" {
  description = "Whether to create a new Route53 hosted zone or use an existing one"
  type        = bool
  default     = false
}

variable "cognito_user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
}

variable "cognito_domain_prefix" {
  description = "Cognito hosted UI domain prefix (must be globally unique)"
  type        = string
}

variable "federate_client_id" {
  description = "OIDC client ID from Amazon Federate service profile"
  type        = string
  sensitive   = true
}

variable "federate_client_secret" {
  description = "OIDC client secret from Amazon Federate service profile"
  type        = string
  sensitive   = true
}

variable "federate_oidc_issuer" {
  description = "OIDC issuer URL for Amazon Federate"
  type        = string
  default     = "https://idp.federate.amazon.com"
}

variable "service_configs" {
  description = "Map of service names to their Cognito app client configuration"
  type = map(object({
    callback_urls = list(string)
    logout_urls   = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
