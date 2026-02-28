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
  bucket_name = "ml-clusters-tfstate-483026362307"
  kms_key_arn = dependency.iam.outputs.kms_key_arn
}
