################################################################################
# Amazon Managed Prometheus (AMP) Workspace
################################################################################

resource "aws_prometheus_workspace" "main" {
  alias = "ml-monitoring-${var.account_name}-${var.aws_region}"

  tags = var.tags
}

################################################################################
# Amazon Managed Grafana (AMG) Workspace
################################################################################

resource "aws_grafana_workspace" "main" {
  name                     = "ml-grafana-${var.account_name}-${var.aws_region}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]

  tags = var.tags
}

################################################################################
# Grafana IAM Role
################################################################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "grafana" {
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
  name = "amp-read-access"
  role = aws_iam_role.grafana.id

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
  name = "cloudwatch-read-access"
  role = aws_iam_role.grafana.id

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

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

################################################################################
# CloudWatch Alarms - S3 Replication Lag
################################################################################

resource "aws_cloudwatch_metric_alarm" "s3_replication_lag" {
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

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}
