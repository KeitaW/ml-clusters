include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/iam.hcl"
  expose = true
}

inputs = {
  cross_account_ids               = ["483026362307"]
  create_terraform_execution_role = false
  create_parallelcluster_roles    = false
  create_hyperpod_role            = true
  create_hyperpod_karpenter_role  = true
  create_s3_replication_role      = false

  # Trust the main account for cross-account role assumption
  terraform_execution_trust_account_ids = ["483026362307"]

  # ArgoCD cross-account access
  create_argocd_spoke_role = true
  argocd_hub_role_arn      = "arn:aws:iam::483026362307:role/ArgoCD-Hub-Controller"
}
