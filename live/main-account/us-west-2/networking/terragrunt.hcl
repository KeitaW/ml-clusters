include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/networking.hcl"
  expose = true
}

inputs = {
  # Single NAT gateway to avoid NAT quota limits in us-west-2
  is_production    = false
  eks_cluster_name = "ml-inference-main-us-west-2"
}
