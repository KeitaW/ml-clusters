include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/iam.hcl"
  expose = true
}

inputs = {
  cross_account_ids              = ["483026362307"]
  create_terraform_execution_role = true
  create_parallelcluster_roles   = false
  create_hyperpod_role           = true
  create_s3_replication_role     = false
}
