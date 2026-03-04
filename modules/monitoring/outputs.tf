output "amp_workspace_id" {
  description = "ID of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.main.id
}

output "amp_workspace_arn" {
  description = "ARN of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.main.arn
}

output "amp_workspace_endpoint" {
  description = "Prometheus endpoint for the AMP workspace"
  value       = aws_prometheus_workspace.main.prometheus_endpoint
}

output "amp_remote_write_endpoint" {
  description = "Remote write endpoint for the AMP workspace"
  value       = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "grafana_workspace_id" {
  description = "ID of the Amazon Managed Grafana workspace"
  value       = var.enable_grafana ? aws_grafana_workspace.main[0].id : ""
}

output "grafana_workspace_endpoint" {
  description = "Endpoint URL for the Grafana workspace"
  value       = var.enable_grafana ? aws_grafana_workspace.main[0].endpoint : ""
}
