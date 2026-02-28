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

run "grafana_workspace" {
  command = plan

  assert {
    condition     = aws_grafana_workspace.main.name == "ml-grafana-test-us-east-1"
    error_message = "AMG workspace name should follow naming convention"
  }

  assert {
    condition     = aws_grafana_workspace.main.account_access_type == "CURRENT_ACCOUNT"
    error_message = "Grafana should only access current account"
  }

  assert {
    condition     = aws_grafana_workspace.main.permission_type == "SERVICE_MANAGED"
    error_message = "Grafana should use service-managed permissions"
  }
}

run "grafana_iam_role" {
  command = plan

  assert {
    condition     = aws_iam_role.grafana.name == "ml-grafana-test-us-east-1"
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
}

run "s3_replication_lag_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag.alarm_name == "s3-replication-lag-test-us-east-1"
    error_message = "Replication lag alarm name should follow convention"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag.threshold == 900
    error_message = "Replication lag threshold should be 900 seconds (15 min RTC target)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag.comparison_operator == "GreaterThanThreshold"
    error_message = "Replication lag alarm should trigger when ABOVE threshold"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.s3_replication_lag.period == 900
    error_message = "Replication lag alarm period should be 900 seconds"
  }
}

run "no_alarm_actions_without_sns" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.s3_replication_lag.alarm_actions) == 0
    error_message = "No alarm actions when SNS topic not provided"
  }
}

run "alarm_actions_with_sns" {
  command = plan

  variables {
    alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:ml-alarms"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.s3_replication_lag.alarm_actions) == 1
    error_message = "Should have exactly one alarm action when SNS topic provided"
  }
}
