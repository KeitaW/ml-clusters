# networking

VPC and network foundation for ML cluster infrastructure.

## Overview

Provisions a VPC with public and private subnets, NAT gateways, EFA security groups, GPU placement groups, and VPC endpoints (S3, ECR). Serves as the foundational network layer consumed by all other modules. Supports both production (one NAT per AZ) and non-production (single NAT) configurations.

## Resources Created

- VPC with DNS support and Kubernetes-tagged subnets (via `terraform-aws-modules/vpc/aws`)
- Public and private subnets across configurable availability zones
- NAT gateway(s) — one per AZ in production, single in non-production
- EFA security group (all self-traffic ingress for GPU communication)
- Cluster placement groups (one per AZ, cluster strategy)
- S3 gateway VPC endpoint
- ECR API and ECR DKR interface VPC endpoints with private DNS

## Usage

```hcl
# live/_envcommon/networking.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/networking"
}

inputs = {
  account_name         = "main"
  aws_region           = "us-east-1"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
  is_production        = false
  eks_cluster_name     = "ml-cluster-main-us-east-1"
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `account_name` | `string` | — | Yes | Account name for resource naming |
| `aws_region` | `string` | — | Yes | AWS region |
| `vpc_cidr` | `string` | — | Yes | VPC CIDR block |
| `availability_zones` | `list(string)` | — | Yes | AZs to deploy into |
| `private_subnet_cidrs` | `list(string)` | — | Yes | Private subnet CIDR blocks |
| `public_subnet_cidrs` | `list(string)` | — | Yes | Public subnet CIDR blocks |
| `is_production` | `bool` | `true` | No | If true, one NAT per AZ; if false, single NAT |
| `eks_cluster_name` | `string` | `""` | No | EKS cluster name for Karpenter subnet discovery tag |
| `additional_private_subnet_tags` | `map(string)` | `{}` | No | Additional tags for private subnets |
| `tags` | `map(string)` | `{}` | No | Additional tags |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | The ID of the VPC |
| `vpc_cidr_block` | The CIDR block of the VPC |
| `private_subnet_ids` | List of private subnet IDs |
| `public_subnet_ids` | List of public subnet IDs |
| `efa_security_group_id` | ID of the EFA security group |
| `placement_group_names` | Map of AZ to placement group name |
| `nat_gateway_ids` | List of NAT Gateway IDs |
| `private_route_table_ids` | List of private route table IDs |

## Dependencies

- None — this is a foundational module
- Required providers: `hashicorp/aws ~> 6.0`
