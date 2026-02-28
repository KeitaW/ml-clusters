output "amp_workspace_id" {
  description = "ID of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.main.id
}

output "amp_workspace_endpoint" {
  description = "Prometheus endpoint for the AMP workspace"
  value       = aws_prometheus_workspace.main.prometheus_endpoint
}

output "grafana_workspace_id" {
  description = "ID of the Amazon Managed Grafana workspace"
  value       = aws_grafana_workspace.main.id
}

output "grafana_workspace_endpoint" {
  description = "Endpoint URL for the Grafana workspace"
  value       = aws_grafana_workspace.main.endpoint
}
