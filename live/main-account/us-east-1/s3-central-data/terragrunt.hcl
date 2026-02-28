include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/s3-data-bucket.hcl"
  expose = true
}

dependency "iam" {
  config_path = "../iam"
}

inputs = {
  bucket_name = "ml-data-central-483026362307-us-east-1"
  kms_key_arn = dependency.iam.outputs.kms_key_arn
}
