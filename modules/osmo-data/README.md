# osmo-data

Aurora PostgreSQL Serverless and ElastiCache Redis for OSMO/Ray workloads.

## Overview

Creates the data layer for OSMO workloads: an Aurora PostgreSQL Serverless v2 cluster (engine 16.6) with AWS-managed credentials in Secrets Manager, and an ElastiCache Serverless Redis 7 cache. Both are KMS-encrypted at rest and accessible only from EKS nodes via dedicated security groups. Aurora uses serverless scaling (configurable min/max ACU) and Redis is capped at 10GB / 5000 ECPU/s.

## Resources Created

- RDS subnet group
- Security group for PostgreSQL (port 5432 from EKS nodes)
- Aurora PostgreSQL Serverless v2 cluster (encrypted, deletion protection, 7-day backup retention)
- Aurora writer instance (db.serverless)
- Security group for Redis (ports 6379-6380 from EKS nodes)
- ElastiCache Serverless Redis 7 (KMS encrypted, 10GB max, 5000 ECPU/s max)

## Usage

```hcl
# live/secondary-account/us-west-2/osmo-data/terragrunt.hcl
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/osmo-data"
}

inputs = {
  vpc_id                     = dependency.networking.outputs.vpc_id
  private_subnet_ids         = dependency.networking.outputs.private_subnet_ids
  kms_key_arn                = dependency.iam.outputs.kms_key_arn
  eks_node_security_group_id = dependency.eks.outputs.node_security_group_id
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name_prefix` | `string` | `"osmo-data"` | No | Prefix for resource names |
| `vpc_id` | `string` | — | Yes | VPC ID |
| `private_subnet_ids` | `list(string)` | — | Yes | Private subnet IDs for RDS and ElastiCache |
| `kms_key_arn` | `string` | — | Yes | KMS key ARN for encryption at rest |
| `eks_node_security_group_id` | `string` | — | Yes | EKS node security group ID (allowed ingress) |
| `db_name` | `string` | `"osmo"` | No | PostgreSQL database name |
| `db_master_username` | `string` | `"osmo_admin"` | No | Aurora master username |
| `db_min_capacity` | `number` | `0.5` | No | Minimum Aurora Serverless v2 ACU |
| `db_max_capacity` | `number` | `4` | No | Maximum Aurora Serverless v2 ACU |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `db_endpoint` | Aurora cluster writer endpoint |
| `db_reader_endpoint` | Aurora cluster reader endpoint |
| `db_port` | Aurora cluster port |
| `db_secret_arn` | Secrets Manager secret ARN with database credentials |
| `redis_endpoint` | ElastiCache Redis endpoint |
| `redis_reader_endpoint` | ElastiCache Redis reader endpoint |
| `redis_port` | ElastiCache Redis port |

## Dependencies

- **networking**: `vpc_id`, `private_subnet_ids`
- **iam**: `kms_key_arn`
- **eks-cluster**: `node_security_group_id`
- Required providers: `hashicorp/aws ~> 6.0`
