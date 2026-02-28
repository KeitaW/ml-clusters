include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/s3-replication"
}

dependency "iam" {
  config_path = "../iam"
}

dependency "s3_central" {
  config_path = "../s3-central-data"
}

dependency "s3_west_replica" {
  config_path = "../../us-west-2/s3-data-replica"
}

dependency "secondary_iam" {
  config_path = "../../../secondary-account/us-west-2/iam"
}

dependency "secondary_s3_replica" {
  config_path = "../../../secondary-account/us-west-2/s3-data-replica"
}

inputs = {
  source_bucket_id = dependency.s3_central.outputs.bucket_id
  iam_role_arn     = dependency.iam.outputs.s3_replication_role_arn
  replication_rules = [
    {
      id                      = "datasets-to-us-west-2"
      prefix                  = "datasets/"
      destination_bucket_arn  = dependency.s3_west_replica.outputs.bucket_arn
      destination_account_id  = "483026362307"
      destination_kms_key_arn = dependency.iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "checkpoints-to-us-west-2"
      prefix                  = "checkpoints/"
      destination_bucket_arn  = dependency.s3_west_replica.outputs.bucket_arn
      destination_account_id  = "483026362307"
      destination_kms_key_arn = dependency.iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "models-to-us-west-2"
      prefix                  = "models/"
      destination_bucket_arn  = dependency.s3_west_replica.outputs.bucket_arn
      destination_account_id  = "483026362307"
      destination_kms_key_arn = dependency.iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "code-to-us-west-2"
      prefix                  = "code/"
      destination_bucket_arn  = dependency.s3_west_replica.outputs.bucket_arn
      destination_account_id  = "483026362307"
      destination_kms_key_arn = dependency.iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "datasets-to-secondary"
      prefix                  = "datasets/"
      destination_bucket_arn  = dependency.secondary_s3_replica.outputs.bucket_arn
      destination_account_id  = "159553542841"
      destination_kms_key_arn = dependency.secondary_iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "checkpoints-to-secondary"
      prefix                  = "checkpoints/"
      destination_bucket_arn  = dependency.secondary_s3_replica.outputs.bucket_arn
      destination_account_id  = "159553542841"
      destination_kms_key_arn = dependency.secondary_iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "models-to-secondary"
      prefix                  = "models/"
      destination_bucket_arn  = dependency.secondary_s3_replica.outputs.bucket_arn
      destination_account_id  = "159553542841"
      destination_kms_key_arn = dependency.secondary_iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
    {
      id                      = "code-to-secondary"
      prefix                  = "code/"
      destination_bucket_arn  = dependency.secondary_s3_replica.outputs.bucket_arn
      destination_account_id  = "159553542841"
      destination_kms_key_arn = dependency.secondary_iam.outputs.kms_key_arn
      storage_class           = "STANDARD"
    },
  ]
}
