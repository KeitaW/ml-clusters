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
