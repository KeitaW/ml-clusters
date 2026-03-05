include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/networking.hcl"
  expose = true
}

inputs = {
  is_production = true

  # Multi-cluster Karpenter discovery tags for OSMO cluster
  additional_private_subnet_tags = {
    "karpenter.sh/discovery/osmo-secondary-us-west-2" = "true"
  }
}
