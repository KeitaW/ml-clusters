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

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
