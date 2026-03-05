variable "grafana_api_key" {
  description = "Grafana API key for authentication"
  type        = string
  sensitive   = true
}

variable "amp_workspace_endpoint" {
  description = "AMP Prometheus endpoint URL"
  type        = string
}

variable "account_name" {
  description = "Account name for data source naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region for SigV4 signing"
  type        = string
}

variable "dashboard_folders" {
  description = "List of Grafana folder names to create (must match top-level dirs under dashboards/)"
  type        = list(string)
  default     = ["Ray", "Infrastructure"]
}
