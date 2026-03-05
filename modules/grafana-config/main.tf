################################################################################
# Grafana Data Source — AMP (Prometheus)
################################################################################

resource "grafana_data_source" "prometheus" {
  type = "prometheus"
  name = "AMP-${var.account_name}-${var.aws_region}"

  json_data_encoded = jsonencode({
    httpMethod    = "POST"
    sigV4Auth     = true
    sigV4AuthType = "workspace-iam-role"
    sigV4Region   = var.aws_region
  })

  url = var.amp_workspace_endpoint
}

################################################################################
# Dashboard Folders
################################################################################

resource "grafana_folder" "folders" {
  for_each = toset(var.dashboard_folders)
  title    = each.value
}

################################################################################
# Dashboards from JSON files
################################################################################

resource "grafana_dashboard" "dashboards" {
  for_each = fileset("${path.module}/dashboards", "**/*.json")

  config_json = templatefile("${path.module}/dashboards/${each.value}", {
    prometheus_uid = grafana_data_source.prometheus.uid
  })

  folder = grafana_folder.folders[
    split("/", each.value)[0]
  ].id

  overwrite = true
}
