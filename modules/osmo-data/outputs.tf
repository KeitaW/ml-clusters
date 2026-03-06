output "db_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.osmo.endpoint
}

output "db_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.osmo.reader_endpoint
}

output "db_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.osmo.port
}

output "db_secret_arn" {
  description = "ARN of the AWS-managed Secrets Manager secret containing database credentials"
  value       = aws_rds_cluster.osmo.master_user_secret[0].secret_arn
}

output "redis_endpoint" {
  description = "ElastiCache Serverless Redis endpoint"
  value       = aws_elasticache_serverless_cache.osmo.endpoint[0].address
}

output "redis_reader_endpoint" {
  description = "ElastiCache Serverless Redis reader endpoint"
  value       = aws_elasticache_serverless_cache.osmo.reader_endpoint[0].address
}

output "redis_port" {
  description = "ElastiCache Serverless Redis port"
  value       = aws_elasticache_serverless_cache.osmo.endpoint[0].port
}
