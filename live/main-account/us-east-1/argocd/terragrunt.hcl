include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/argocd"
}

dependency "eks_hub" {
  config_path = "../eks-cluster"
}

dependency "midway_auth" {
  config_path = "../midway-auth"
}

dependency "monitoring" {
  config_path = "../monitoring"
}

dependency "eks_spoke_west2" {
  config_path = "../../us-west-2/eks-cluster"

  mock_outputs = {
    cluster_name                       = "ml-cluster-main-us-west-2"
    cluster_endpoint                   = "https://mock-endpoint.eks.us-west-2.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    vpc_id                             = "vpc-mock"
    alb_controller_role_arn            = "arn:aws:iam::483026362307:role/mock"
    karpenter_node_role_arn            = "arn:aws:iam::483026362307:role/mock"
    karpenter_queue_name               = "mock-queue"
    karpenter_instance_profile_name    = "mock-profile"
    adot_role_arn                      = ""
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks_secondary" {
  config_path = "../../../secondary-account/us-west-2/eks-cluster"

  mock_outputs = {
    cluster_name                       = "ml-training-secondary-us-west-2"
    cluster_endpoint                   = "https://mock-endpoint.eks.us-west-2.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    vpc_id                             = "vpc-mock"
    alb_controller_role_arn            = "arn:aws:iam::159553542841:role/mock"
    karpenter_node_role_arn            = "arn:aws:iam::159553542841:role/mock"
    karpenter_queue_name               = "mock-queue"
    karpenter_instance_profile_name    = "mock-profile"
    adot_role_arn                      = ""
  }
  # Secondary account not yet deployed — allow mocks on apply until TerraformExecutionRole exists
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
}

dependency "eks_secondary_east1" {
  config_path = "../../../secondary-account/us-east-1/eks-cluster"

  mock_outputs = {
    cluster_name                       = "ml-training-secondary-us-east-1"
    cluster_endpoint                   = "https://mock-endpoint.eks.us-east-1.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    vpc_id                             = "vpc-mock"
    alb_controller_role_arn            = "arn:aws:iam::159553542841:role/mock"
    karpenter_node_role_arn            = "arn:aws:iam::159553542841:role/mock"
    karpenter_queue_name               = "mock-queue"
    karpenter_instance_profile_name    = "mock-profile"
    adot_role_arn                      = ""
    ray_role_arn                       = ""
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "monitoring_secondary_east1" {
  config_path = "../../../secondary-account/us-east-1/monitoring"

  mock_outputs = {
    amp_remote_write_endpoint = "https://mock-aps.us-east-1.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
}

dependency "eks_osmo" {
  config_path = "../../../secondary-account/us-west-2/osmo-eks"

  mock_outputs = {
    cluster_name                       = "osmo-secondary-us-west-2"
    cluster_endpoint                   = "https://mock-endpoint.eks.us-west-2.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    vpc_id                             = "vpc-mock"
    karpenter_node_role_name           = "KarpenterNode-mock"
    karpenter_node_role_arn            = "arn:aws:iam::159553542841:role/mock"
    karpenter_queue_name               = "mock-queue"
    karpenter_instance_profile_name    = ""
    adot_role_arn                      = ""
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "monitoring_secondary_west2" {
  config_path = "../../../secondary-account/us-west-2/monitoring"

  mock_outputs = {
    amp_remote_write_endpoint = "https://mock-aps.us-west-2.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy"]
}

inputs = {
  cluster_name           = dependency.eks_hub.outputs.cluster_name
  cluster_endpoint       = dependency.eks_hub.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.eks_hub.outputs.cluster_certificate_authority_data
  assume_role_arn        = "arn:aws:iam::483026362307:role/TerraformExecutionRole"

  # Hub OIDC for IRSA
  oidc_provider_arn = dependency.eks_hub.outputs.oidc_provider_arn
  oidc_provider     = dependency.eks_hub.outputs.oidc_provider

  # Hub GitOps Bridge annotations
  hub_annotations = {
    aws_account_id             = "483026362307"
    aws_region                 = "us-east-1"
    cluster_type               = "training"
    vpc_id                     = dependency.eks_hub.outputs.vpc_id
    alb_controller_role_arn    = dependency.eks_hub.outputs.alb_controller_role_arn
    external_dns_role_arn      = dependency.eks_hub.outputs.external_dns_role_arn
    adot_role_arn              = dependency.eks_hub.outputs.adot_role_arn
    karpenter_node_role_arn    = dependency.eks_hub.outputs.karpenter_node_role_arn
    karpenter_queue_name       = dependency.eks_hub.outputs.karpenter_queue_name
    karpenter_instance_profile = dependency.eks_hub.outputs.karpenter_instance_profile_name
    amp_region                 = "us-east-1"
    amp_remote_write_endpoint  = dependency.monitoring.outputs.amp_remote_write_endpoint
    enable_karpenter           = "true"
    enable_external_dns        = "true"
    enable_adot                = "true"
  }

  # Spoke clusters
  spoke_clusters = {
    "ml-cluster-main-us-west-2" = {
      name         = "ml-cluster-main-us-west-2"
      server       = dependency.eks_spoke_west2.outputs.cluster_endpoint
      ca_data      = dependency.eks_spoke_west2.outputs.cluster_certificate_authority_data
      cluster_name = dependency.eks_spoke_west2.outputs.cluster_name
      # Same account — no role_arn needed
      annotations = {
        aws_account_id             = "483026362307"
        aws_region                 = "us-west-2"
        cluster_type               = "inference"
        vpc_id                     = dependency.eks_spoke_west2.outputs.vpc_id
        alb_controller_role_arn    = dependency.eks_spoke_west2.outputs.alb_controller_role_arn
        adot_role_arn              = dependency.eks_spoke_west2.outputs.adot_role_arn
        karpenter_node_role_arn    = dependency.eks_spoke_west2.outputs.karpenter_node_role_arn
        karpenter_queue_name       = dependency.eks_spoke_west2.outputs.karpenter_queue_name
        karpenter_instance_profile = dependency.eks_spoke_west2.outputs.karpenter_instance_profile_name
        amp_region                 = "us-east-1"
        amp_remote_write_endpoint  = dependency.monitoring.outputs.amp_remote_write_endpoint
        enable_karpenter           = "true"
        enable_external_dns        = "false"
        enable_adot                = "true"
      }
    }
    "ml-training-secondary-us-west-2" = {
      name         = "ml-training-secondary-us-west-2"
      server       = dependency.eks_secondary.outputs.cluster_endpoint
      ca_data      = dependency.eks_secondary.outputs.cluster_certificate_authority_data
      cluster_name = dependency.eks_secondary.outputs.cluster_name
      role_arn     = "arn:aws:iam::159553542841:role/ArgoCD-Spoke-Access"
      annotations = {
        aws_account_id             = "159553542841"
        aws_region                 = "us-west-2"
        cluster_type               = "training"
        vpc_id                     = dependency.eks_secondary.outputs.vpc_id
        alb_controller_role_arn    = dependency.eks_secondary.outputs.alb_controller_role_arn
        karpenter_node_role_arn    = dependency.eks_secondary.outputs.karpenter_node_role_arn
        karpenter_queue_name       = dependency.eks_secondary.outputs.karpenter_queue_name
        karpenter_instance_profile = dependency.eks_secondary.outputs.karpenter_instance_profile_name
        amp_region                 = "us-east-1"
        amp_remote_write_endpoint  = dependency.monitoring.outputs.amp_remote_write_endpoint
        enable_karpenter           = "true"
        enable_external_dns        = "false"
        enable_adot                = "true"
      }
    }
    "ml-training-secondary-us-east-1" = {
      name         = "ml-training-secondary-us-east-1"
      server       = dependency.eks_secondary_east1.outputs.cluster_endpoint
      ca_data      = dependency.eks_secondary_east1.outputs.cluster_certificate_authority_data
      cluster_name = dependency.eks_secondary_east1.outputs.cluster_name
      role_arn     = "arn:aws:iam::159553542841:role/ArgoCD-Spoke-Access"
      annotations = {
        aws_account_id             = "159553542841"
        aws_region                 = "us-east-1"
        cluster_type               = "training"
        vpc_id                     = dependency.eks_secondary_east1.outputs.vpc_id
        alb_controller_role_arn    = dependency.eks_secondary_east1.outputs.alb_controller_role_arn
        adot_role_arn              = dependency.eks_secondary_east1.outputs.adot_role_arn
        karpenter_node_role_arn    = dependency.eks_secondary_east1.outputs.karpenter_node_role_arn
        karpenter_queue_name       = dependency.eks_secondary_east1.outputs.karpenter_queue_name
        karpenter_instance_profile = dependency.eks_secondary_east1.outputs.karpenter_instance_profile_name
        ray_role_arn               = dependency.eks_secondary_east1.outputs.ray_role_arn
        amp_region                 = "us-east-1"
        amp_remote_write_endpoint  = dependency.monitoring_secondary_east1.outputs.amp_remote_write_endpoint
        enable_karpenter           = "true"
        enable_external_dns        = "false"
        enable_adot                = "true"
        enable_kuberay             = "true"
      }
    }
    "osmo-secondary-us-west-2" = {
      name         = "osmo-secondary-us-west-2"
      server       = dependency.eks_osmo.outputs.cluster_endpoint
      ca_data      = dependency.eks_osmo.outputs.cluster_certificate_authority_data
      cluster_name = dependency.eks_osmo.outputs.cluster_name
      role_arn     = "arn:aws:iam::159553542841:role/ArgoCD-Spoke-Access"
      annotations = {
        aws_account_id             = "159553542841"
        aws_region                 = "us-west-2"
        cluster_type               = "osmo"
        vpc_id                     = dependency.eks_osmo.outputs.vpc_id
        karpenter_node_role_name   = dependency.eks_osmo.outputs.karpenter_node_role_name
        karpenter_node_role_arn    = dependency.eks_osmo.outputs.karpenter_node_role_arn
        karpenter_queue_name       = dependency.eks_osmo.outputs.karpenter_queue_name
        adot_role_arn              = dependency.eks_osmo.outputs.adot_role_arn
        amp_region                 = "us-west-2"
        amp_remote_write_endpoint  = dependency.monitoring_secondary_west2.outputs.amp_remote_write_endpoint
        enable_karpenter           = "true"
        enable_osmo_karpenter      = "true"
        enable_external_dns        = "false"
        enable_adot                = "true"
      }
    }
  }

  # Midway authentication
  enable_cognito_auth      = true
  acm_certificate_arn      = dependency.midway_auth.outputs.acm_certificate_arn
  argocd_hostname          = "argocd.mlkeita.people.aws.dev"
  alb_ingress_group_name   = "ml-cluster-services"
  cognito_user_pool_arn    = dependency.midway_auth.outputs.cognito_user_pool_arn
  cognito_app_client_id    = dependency.midway_auth.outputs.cognito_app_client_ids["argocd"]
  cognito_user_pool_domain = dependency.midway_auth.outputs.cognito_user_pool_domain

  # ApplicationSet bootstrap
  enable_applicationset_bootstrap = true
  git_repo_url                    = "https://github.com/KeitaW/ml-clusters.git"
}
