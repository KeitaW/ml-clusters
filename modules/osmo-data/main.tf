################################################################################
# Aurora PostgreSQL Serverless v2
################################################################################

resource "aws_db_subnet_group" "osmo" {
  name       = var.name_prefix
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

# No egress rules — RDS only responds to inbound connections (stateful SG)
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Allow PostgreSQL access from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [var.eks_node_security_group_id]
  }

  tags = var.tags
}

resource "aws_rds_cluster" "osmo" {
  cluster_identifier = var.name_prefix
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.6"
  database_name      = var.db_name
  master_username    = var.db_master_username

  # AWS-managed password in Secrets Manager — keeps credentials out of Terraform state
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.osmo.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  serverlessv2_scaling_configuration {
    min_capacity = var.db_min_capacity
    max_capacity = var.db_max_capacity
  }

  backup_retention_period = 7
  deletion_protection     = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-final"

  tags = var.tags
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name_prefix}-writer"
  cluster_identifier = aws_rds_cluster.osmo.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.osmo.engine
  engine_version     = aws_rds_cluster.osmo.engine_version

  tags = var.tags
}

################################################################################
# ElastiCache Serverless Redis
################################################################################

# No egress rules — ElastiCache only responds to inbound connections (stateful SG)
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis"
  description = "Allow Redis access from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis primary + reader from EKS nodes"
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6380
    security_groups = [var.eks_node_security_group_id]
  }

  tags = var.tags
}

resource "aws_elasticache_serverless_cache" "osmo" {
  engine = "redis"
  name   = var.name_prefix

  major_engine_version = "7"

  cache_usage_limits {
    data_storage {
      maximum = 10
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.redis.id]
  kms_key_id         = var.kms_key_arn

  tags = var.tags
}
