# grafana-config

Grafana dashboards and AMP data source configuration.

## Overview

Configures an existing Amazon Managed Grafana workspace with an AMP data source (SigV4 auth), dashboard folders, and JSON dashboards. Uses the Grafana Terraform provider to manage resources directly via the Grafana API. Dashboard JSON files are loaded from the `dashboards/` subdirectory and support a `__PROMETHEUS_UID__` placeholder for data source binding.

## Resources Created

- Grafana data source (Prometheus/AMP with SigV4 signing)
- Grafana folders (one per entry in `dashboard_folders`)
- Grafana dashboards (one per JSON file under `dashboards/{folder_name}/`)

## Usage

```hcl
# live/secondary-account/us-east-1/grafana-config/terragrunt.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/grafana-config"
}

inputs = {
  grafana_api_key        = dependency.monitoring.outputs.grafana_service_account_token
  amp_workspace_endpoint = dependency.monitoring.outputs.amp_workspace_endpoint
  account_name           = "secondary"
  aws_region             = "us-east-1"
  dashboard_folders      = ["Ray", "Infrastructure"]
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `grafana_api_key` | `string` (sensitive) | — | Yes | Grafana API key for authentication |
| `amp_workspace_endpoint` | `string` | — | Yes | AMP Prometheus endpoint URL |
| `account_name` | `string` | — | Yes | Account name for data source naming |
| `aws_region` | `string` | — | Yes | AWS region for SigV4 signing |
| `dashboard_folders` | `list(string)` | `["Ray", "Infrastructure"]` | No | Grafana folder names (must match dirs under `dashboards/`) |

## Outputs

None.

## Dependencies

- **monitoring**: `amp_workspace_endpoint`, `grafana_service_account_token`
- Dashboard JSON files must exist under `modules/grafana-config/dashboards/{folder_name}/*.json`
- Required providers: `grafana/grafana ~> 4.0`
