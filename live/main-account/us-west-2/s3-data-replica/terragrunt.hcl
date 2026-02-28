include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/s3-data-bucket.hcl"
  expose = true
}

dependency "iam" {
  config_path = "../../main-account/us-east-1/iam"
}

inputs = {
  bucket_name                = "ml-data-replica-483026362307-us-west-2"
  kms_key_arn                = dependency.iam.outputs.kms_key_arn
  replication_source_role_arns = [dependency.iam.outputs.s3_replication_role_arn]
}
