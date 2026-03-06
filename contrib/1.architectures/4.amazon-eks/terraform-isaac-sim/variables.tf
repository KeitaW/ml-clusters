variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "isaac-sim-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gpu_instance_types" {
  description = "GPU instance types for Isaac Sim rendering"
  type        = list(string)
  default     = ["g5.2xlarge", "g5.4xlarge", "g6.2xlarge"]
}

variable "max_gpu_nodes" {
  description = "Maximum number of rendering GPU nodes Karpenter can provision"
  type        = number
  default     = 4
}

variable "max_training_gpus" {
  description = "Maximum number of training GPUs Karpenter can provision"
  type        = number
  default     = 48
}

variable "training_instance_type" {
  description = "Instance type for training NodePool (e.g., p5.48xlarge, p6-b300.48xlarge)"
  type        = string
  default     = "p6-b300.48xlarge"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
