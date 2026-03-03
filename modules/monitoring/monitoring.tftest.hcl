mock_provider "aws" {}

variables {
  account_name       = "test"
  aws_region         = "us-east-1"
  vpc_id             = "vpc-test12345"
  private_subnet_ids = ["subnet-a", "subnet-b"]
}

run "prometheus_workspace" {
  command = plan

  assert {
    condition     = aws_prometheus_workspace.main.alias == "ml-monitoring-test-us-east-1"
    error_message = "AMP workspace alias should follow naming convention"
  }
}

run "sns_topic" {
  command = plan

  assert {
    condition     = aws_sns_topic.alerts.name == "ml-cluster-alerts-test-us-east-1"
    error_message = "SNS topic name should follow naming convention"
  }
}

run "grafana_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_grafana_workspace.main) == 0
    error_message = "Grafana should not be created when enable_grafana is false"
  }

  assert {
    condition     = length(aws_iam_role.grafana) == 0
    error_message = "Grafana IAM role should not be created when enable_grafana is false"
  }
}

run "grafana_enabled" {
  command = plan

  variables {
    enable_grafana = true
  }

  assert {
    condition     = aws_grafana_workspace.main[0].name == "ml-grafana-test-us-east-1"
    error_message = "AMG workspace name should follow naming convention"
  }

  assert {
    condition     = aws_grafana_workspace.main[0].account_access_type == "CURRENT_ACCOUNT"
    error_message = "Grafana should only access current account"
  }

  assert {
    condition     = aws_grafana_workspace.main[0].permission_type == "CUSTOMER_MANAGED"
    error_message = "Grafana should use customer-managed permissions"
  }

  assert {
    condition     = aws_iam_role.grafana[0].name == "ml-grafana-test-us-east-1"
    error_message = "Grafana IAM role name should follow naming convention"
  }
}

run "subnet_ip_exhaustion_alarms" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.subnet_ip_exhaustion) == 2
    error_message = "Should create one IP exhaustion alarm per private subnet"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.subnet_ip_exhaustion["subnet-a"].comparison_operator == "LessThanThreshold"
    error_message = "IP alarm should trigger when IPs drop BELOW threshold"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.subnet_ip_exhaustion["subnet-a"].threshold == 50
    error_message = "IP alarm threshold should be 50 available IPs"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.subnet_ip_exhaustion["subnet-a"].metric_name == "AvailableIpAddressCount"
    error_message = "IP alarm should monitor AvailableIpAddressCount metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.subnet_ip_exhaustion["subnet-a"].namespace == "AWS/EC2"
    error_message = "IP alarm should use AWS/EC2 namespace"
  }

  # SNS topic is always created now — alarms always have actions
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.subnet_ip_exhaustion["subnet-a"].alarm_actions) == 1
    error_message = "Subnet alarm should have SNS action"
  }
}

run "s3_replication_alarm_skipped_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.s3_replication_lag) == 0
    error_message = "S3 replication alarm should not be created when bucket name is empty"
  }
}

run "s3_replication_alarm_with_config" {
  command = plan

  variables {
    s3_replication_bucket_name      = "ml-data-source"
    s3_replication_dest_bucket_name = "ml-data-dest"
    s3_replication_rule_id          = "replicate-all"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag[0].alarm_name == "s3-replication-lag-test-us-east-1"
    error_message = "Replication lag alarm name should follow convention"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag[0].threshold == 900
    error_message = "Replication lag threshold should be 900 seconds (15 min RTC target)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag[0].comparison_operator == "GreaterThanThreshold"
    error_message = "Replication lag alarm should trigger when ABOVE threshold"
  }
}
