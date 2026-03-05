################################################################################
# Aurora PostgreSQL Serverless v2
################################################################################

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name       = "osmo/database-credentials"
  kms_key_id = var.kms_key_arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db.result
    dbname   = var.db_name
    engine   = "postgres"
    host     = aws_rds_cluster.osmo.endpoint
    port     = aws_rds_cluster.osmo.port
  })
}

resource "aws_db_subnet_group" "osmo" {
  name       = "osmo-data"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "rds" {
  name        = "osmo-rds"
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
  cluster_identifier = "osmo-data"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.6"
  database_name      = var.db_name
  master_username    = var.db_master_username
  master_password    = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.osmo.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  serverlessv2_scaling_configuration {
    min_capacity = var.db_min_capacity
    max_capacity = var.db_max_capacity
  }

  skip_final_snapshot       = false
  final_snapshot_identifier = "osmo-data-final"

  tags = var.tags
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "osmo-data-writer"
  cluster_identifier = aws_rds_cluster.osmo.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.osmo.engine
  engine_version     = aws_rds_cluster.osmo.engine_version

  tags = var.tags
}

################################################################################
# ElastiCache Serverless Redis
################################################################################

resource "aws_security_group" "redis" {
  name        = "osmo-redis"
  description = "Allow Redis access from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS nodes"
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    security_groups = [var.eks_node_security_group_id]
  }

  tags = var.tags
}

resource "aws_elasticache_serverless_cache" "osmo" {
  engine = "redis"
  name   = "osmo-data"

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
