resource "aws_s3_bucket_replication_configuration" "this" {
  bucket = var.source_bucket_id
  role   = var.iam_role_arn

  dynamic "rule" {
    for_each = var.replication_rules

    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        account       = rule.value.destination_account_id
        storage_class = rule.value.storage_class

        encryption_configuration {
          replica_kms_key_id = rule.value.destination_kms_key_arn
        }

        access_control_translation {
          owner = "Destination"
        }

        replication_time {
          status = "Enabled"
          time {
            minutes = 15
          }
        }

        metrics {
          status = "Enabled"
          event_threshold {
            minutes = 15
          }
        }
      }

      delete_marker_replication {
        status = "Enabled"
      }
    }
  }
}
