include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/iam.hcl"
  expose = true
}

inputs = {
  # Only create the regional KMS key — all IAM roles are account-wide
  # and already managed by us-east-1/iam
  create_terraform_execution_role = false
  create_parallelcluster_roles    = false
  create_hyperpod_role            = false
  create_s3_replication_role      = false
}
