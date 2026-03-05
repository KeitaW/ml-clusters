include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/grafana-config"
}

dependency "monitoring" {
  config_path = "../monitoring"

  mock_outputs = {
    grafana_workspace_endpoint    = "g-mock.grafana-workspace.us-east-1.amazonaws.com"
    grafana_service_account_token = "mock-token"
    amp_workspace_endpoint        = "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

generate "grafana_provider" {
  path      = "grafana_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "grafana" {
      url  = "https://${dependency.monitoring.outputs.grafana_workspace_endpoint}"
      auth = var.grafana_api_key
    }
  EOF
}

inputs = {
  grafana_api_key        = dependency.monitoring.outputs.grafana_service_account_token
  amp_workspace_endpoint = dependency.monitoring.outputs.amp_workspace_endpoint
  account_name           = "secondary"
  aws_region             = "us-east-1"
  dashboard_folders      = ["Ray", "Infrastructure"]
}
