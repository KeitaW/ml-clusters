include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/shared-storage.hcl"
  expose = true
}

dependency "networking" {
  config_path = "../networking"
}

dependency "iam" {
  config_path = "../iam"
}

dependency "s3_central" {
  config_path = "../s3-central-data"
}

inputs = {
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids
  kms_key_arn        = dependency.iam.outputs.kms_key_arn
  s3_data_bucket_arn = dependency.s3_central.outputs.bucket_arn
  fsx_storage_capacity    = 4800
  fsx_throughput_per_unit = 500
}
