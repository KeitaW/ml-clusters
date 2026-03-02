variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the EKS cluster"
  type        = string
}

variable "atlantis_chart_version" {
  description = "Version of the Atlantis Helm chart"
  type        = string
  default     = "5.12.0"
}

variable "atlantis_namespace" {
  description = "Kubernetes namespace for Atlantis"
  type        = string
  default     = "atlantis"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "atlantis_repo_allowlist" {
  description = "List of repositories Atlantis is allowed to operate on"
  type        = list(string)
  default     = ["github.com/your-org/ml-clusters"]
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume when authenticating to the EKS cluster"
  type        = string
  default     = ""
}

variable "github_user" {
  description = "GitHub username for Atlantis"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT for Atlantis"
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting the Secrets Manager secret"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_cognito_auth" {
  description = "Enable Cognito authentication on the ALB for non-webhook paths"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS on the ALB"
  type        = string
  default     = ""
}

variable "atlantis_hostname" {
  description = "Hostname for Atlantis (e.g., atlantis.mlkeita.people.aws.dev)"
  type        = string
  default     = ""
}

variable "alb_ingress_group_name" {
  description = "ALB Ingress Group name for sharing ALB across services"
  type        = string
  default     = "ml-cluster-services"
}

variable "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool for ALB authentication"
  type        = string
  default     = ""
}

variable "cognito_app_client_id" {
  description = "Cognito App Client ID for Atlantis"
  type        = string
  default     = ""
}

variable "cognito_user_pool_domain" {
  description = "Cognito User Pool domain for the hosted UI"
  type        = string
  default     = ""
}
