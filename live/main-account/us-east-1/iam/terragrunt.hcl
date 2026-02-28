include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/iam.hcl"
  expose = true
}

inputs = {
  cross_account_ids              = ["159553542841"]
  create_terraform_execution_role = true
  create_parallelcluster_roles   = true
  create_hyperpod_role           = false
  create_s3_replication_role     = true
}
