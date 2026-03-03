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

variable "argocd_chart_version" {
  description = "Version of the ArgoCD Helm chart"
  type        = string
  default     = "7.8.0"
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "spoke_clusters" {
  description = "Spoke clusters to register with ArgoCD"
  type = map(object({
    name    = string
    server  = string
    ca_data = string
  }))
  default = {}
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume when authenticating to the EKS cluster"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_cognito_auth" {
  description = "Enable Cognito authentication on the ALB ingress"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS on the ALB"
  type        = string
  default     = ""
}

variable "argocd_hostname" {
  description = "Hostname for ArgoCD (e.g., argocd.mlkeita.people.aws.dev)"
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
  description = "Cognito App Client ID for ArgoCD"
  type        = string
  default     = ""
}

variable "cognito_user_pool_domain" {
  description = "Cognito User Pool domain for the hosted UI"
  type        = string
  default     = ""
}

variable "enable_applicationset_bootstrap" {
  description = "Apply the cluster-addons ApplicationSet to bootstrap GitOps add-ons"
  type        = bool
  default     = false
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD ApplicationSet source"
  type        = string
  default     = ""
}
