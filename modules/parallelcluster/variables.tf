variable "region" {
  description = "AWS region"
  type        = string
}

variable "deploy_pcluster_api" {
  description = "Deploy the PCluster API (one-time per account/region)"
  type        = bool
  default     = true
}

variable "api_stack_name" {
  description = "Override API stack name"
  type        = string
  default     = ""
}

variable "api_version" {
  description = "Version of ParallelCluster API to deploy"
  type        = string
  default     = "3.12.0"
}

variable "cluster_configs" {
  description = "Map of cluster configurations"
  type = map(object({
    config_path             = string
    head_node_subnet_id     = string
    compute_subnet_id       = string
    fsx_filesystem_id       = string
    efs_filesystem_id       = string
    capacity_reservation_id = optional(string, "")
  }))
}
