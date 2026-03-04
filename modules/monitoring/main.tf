################################################################################
# Amazon Managed Prometheus (AMP) Workspace
################################################################################

resource "aws_prometheus_workspace" "main" {
  alias = "ml-monitoring-${var.account_name}-${var.aws_region}"

  tags = var.tags
}

################################################################################
# SNS Topic for Alarm Notifications
################################################################################

resource "aws_sns_topic" "alerts" {
  name = "ml-cluster-alerts-${var.account_name}-${var.aws_region}"

  tags = var.tags
}

# Allow AMP Alertmanager to publish to this topic
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAMPAlertmanagerPublish"
        Effect    = "Allow"
        Principal = { Service = "aps.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowGrafanaPublish"
        Effect    = "Allow"
        Principal = { Service = "grafana.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

################################################################################
# Prometheus Alertmanager Definition
################################################################################

resource "aws_prometheus_alert_manager_definition" "main" {
  workspace_id = aws_prometheus_workspace.main.id

  definition = yamlencode({
    alertmanager_config = <<-ALERTMANAGER
      route:
        receiver: sns
        group_by: ['alertname', 'severity']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
      receivers:
        - name: sns
          sns_configs:
            - topic_arn: ${aws_sns_topic.alerts.arn}
              sigv4:
                region: ${var.aws_region}
              message: |
                {{ range .Alerts }}
                Alert: {{ .Labels.alertname }}
                Severity: {{ .Labels.severity }}
                Summary: {{ .Annotations.summary }}
                Description: {{ .Annotations.description }}
                {{ end }}
    ALERTMANAGER
  })
}

################################################################################
# Amazon Managed Grafana (AMG) Workspace — conditional on enable_grafana
################################################################################

resource "aws_grafana_workspace" "main" {
  count = var.enable_grafana ? 1 : 0

  name                      = "ml-grafana-${var.account_name}-${var.aws_region}"
  account_access_type       = "CURRENT_ACCOUNT"
  authentication_providers  = var.grafana_auth_providers
  permission_type           = "CUSTOMER_MANAGED"
  role_arn                  = aws_iam_role.grafana[0].arn
  data_sources              = ["PROMETHEUS", "CLOUDWATCH"]
  grafana_version           = var.grafana_version
  notification_destinations = ["SNS"]

  tags = var.tags
}

################################################################################
# Grafana IAM Role — conditional on enable_grafana
################################################################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name = "ml-grafana-${var.account_name}-${var.aws_region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "grafana_amp_read" {
  count = var.enable_grafana ? 1 : 0

  name = "amp-read-access"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "grafana_cloudwatch_read" {
  count = var.enable_grafana ? 1 : 0

  name = "cloudwatch-read-access"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "grafana_sns_publish" {
  count = var.enable_grafana ? 1 : 0

  name = "sns-publish-access"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

################################################################################
# Grafana Role Associations — conditional on non-empty ID lists
################################################################################

resource "aws_grafana_role_association" "admin" {
  count = var.enable_grafana && length(var.grafana_admin_user_ids) > 0 ? 1 : 0

  workspace_id = aws_grafana_workspace.main[0].id
  role         = "ADMIN"
  user_ids     = var.grafana_admin_user_ids
}

resource "aws_grafana_role_association" "editor" {
  count = var.enable_grafana && length(var.grafana_editor_group_ids) > 0 ? 1 : 0

  workspace_id = aws_grafana_workspace.main[0].id
  role         = "EDITOR"
  group_ids    = var.grafana_editor_group_ids
}

resource "aws_grafana_role_association" "viewer" {
  count = var.enable_grafana && length(var.grafana_viewer_group_ids) > 0 ? 1 : 0

  workspace_id = aws_grafana_workspace.main[0].id
  role         = "VIEWER"
  group_ids    = var.grafana_viewer_group_ids
}

################################################################################
# Prometheus Alerting Rules
################################################################################

resource "aws_prometheus_rule_group_namespace" "ml_alerts" {
  name         = "ml-alerts"
  workspace_id = aws_prometheus_workspace.main.id

  data = yamlencode({
    groups = [
      {
        name = "ml-cluster-alerts"
        rules = [
          {
            alert = "GPUIdle"
            expr  = "avg(DCGM_FI_DEV_GPU_UTIL) by (instance) < 10"
            for   = "15m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "GPU utilization is below 10% on {{ $labels.instance }}"
              description = "GPU on instance {{ $labels.instance }} has been idle (utilization < 10%) for more than 15 minutes. Consider releasing unused GPU resources."
            }
          },
          {
            alert = "EFAStalled"
            expr  = "rate(efa_rdma_read_resp_bytes_total[5m]) == 0"
            for   = "10m"
            labels = {
              severity = "critical"
            }
            annotations = {
              summary     = "EFA RDMA traffic stalled on {{ $labels.instance }}"
              description = "EFA RDMA read response bytes rate has been zero for more than 10 minutes on {{ $labels.instance }}. This may indicate a network fabric issue or stalled distributed training job."
            }
          },
          {
            alert = "FSxIOPSHigh"
            expr  = "fsx_disk_iops_total > 50000"
            for   = "5m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "FSx IOPS approaching limit on {{ $labels.instance }}"
              description = "FSx total disk IOPS has exceeded 50,000 on {{ $labels.instance }} for more than 5 minutes. This is approaching the filesystem IOPS limit and may cause I/O throttling."
            }
          },
        ]
      }
    ]
  })
}

################################################################################
# CloudWatch Alarms - Subnet IP Exhaustion
################################################################################

resource "aws_cloudwatch_metric_alarm" "subnet_ip_exhaustion" {
  for_each = toset(var.private_subnet_ids)

  alarm_name          = "subnet-ip-exhaustion-${each.value}"
  alarm_description   = "Available IP addresses in subnet ${each.value} are running low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AvailableIpAddressCount"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Minimum"
  threshold           = 50
  treat_missing_data  = "notBreaching"

  dimensions = {
    SubnetId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

################################################################################
# CloudWatch Alarms - S3 Replication Lag (only when replication is configured)
################################################################################

resource "aws_cloudwatch_metric_alarm" "s3_replication_lag" {
  count = var.s3_replication_bucket_name != "" ? 1 : 0

  alarm_name          = "s3-replication-lag-${var.account_name}-${var.aws_region}"
  alarm_description   = "S3 replication latency exceeds 15 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 900
  statistic           = "Maximum"
  threshold           = 900
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket     = var.s3_replication_bucket_name
    DestinationBucket = var.s3_replication_dest_bucket_name
    RuleId           = var.s3_replication_rule_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}
