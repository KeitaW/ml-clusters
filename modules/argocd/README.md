# argocd

ArgoCD deployment with hub-spoke multi-cluster management and ApplicationSet bootstrap.

## Overview

Deploys ArgoCD via Helm on the hub EKS cluster with IRSA for cross-cluster authentication. Supports hub-spoke multi-cluster management by registering spoke clusters as Kubernetes secrets with `awsAuthConfig`. Optionally enables Cognito-authenticated ALB ingress and an ApplicationSet bootstrap application for GitOps-driven add-on deployment.

## Resources Created

- ArgoCD Helm release (argo-cd chart, ClusterIP service)
- ArgoCD application controller IRSA role (`ArgoCD-Hub-Controller`) with EKS describe and spoke role assume permissions
- ArgoCD namespace
- Hub cluster self-registration secret with GitOps Bridge annotations
- Spoke cluster secrets with cross-account `awsAuthConfig` (when `spoke_clusters` is set)
- ALB Ingress with Cognito authentication (when `enable_cognito_auth` is true)
- Bootstrap Application for ApplicationSet deployment (when `enable_applicationset_bootstrap` is true)

## Usage

```hcl
# live/main-account/us-east-1/argocd/terragrunt.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/argocd"
}

inputs = {
  cluster_name           = dependency.eks.outputs.cluster_name
  cluster_endpoint       = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn      = dependency.eks.outputs.oidc_provider_arn
  oidc_provider          = dependency.eks.outputs.oidc_provider

  enable_cognito_auth           = true
  acm_certificate_arn           = dependency.midway_auth.outputs.acm_certificate_arn
  argocd_hostname               = "argocd.mlkeita.people.aws.dev"
  cognito_user_pool_arn         = dependency.midway_auth.outputs.cognito_user_pool_arn
  enable_applicationset_bootstrap = true
  git_repo_url                  = "https://github.com/KeitaW/ml-clusters"
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `cluster_name` | `string` | — | Yes | EKS cluster name |
| `cluster_endpoint` | `string` | — | Yes | EKS cluster endpoint URL |
| `cluster_ca_certificate` | `string` | — | Yes | Base64-encoded cluster CA certificate |
| `oidc_provider_arn` | `string` | — | Yes | OIDC provider ARN for IRSA |
| `oidc_provider` | `string` | — | Yes | OIDC provider URL |
| `argocd_chart_version` | `string` | `"7.8.0"` | No | ArgoCD Helm chart version |
| `argocd_namespace` | `string` | `"argocd"` | No | Kubernetes namespace |
| `hub_annotations` | `map(string)` | `{}` | No | GitOps Bridge annotations for the hub cluster |
| `spoke_clusters` | `map(object)` | `{}` | No | Spoke clusters to register |
| `assume_role_arn` | `string` | `""` | No | IAM role ARN for cluster authentication |
| `enable_cognito_auth` | `bool` | `false` | No | Enable Cognito ALB authentication |
| `acm_certificate_arn` | `string` | `""` | No | ACM certificate ARN for HTTPS |
| `argocd_hostname` | `string` | `""` | No | Hostname for ArgoCD |
| `alb_ingress_group_name` | `string` | `"ml-cluster-services"` | No | Shared ALB IngressGroup name |
| `cognito_user_pool_arn` | `string` | `""` | No | Cognito User Pool ARN |
| `cognito_app_client_id` | `string` | `""` | No | Cognito App Client ID |
| `cognito_user_pool_domain` | `string` | `""` | No | Cognito User Pool domain |
| `enable_applicationset_bootstrap` | `bool` | `false` | No | Deploy bootstrap ApplicationSet |
| `git_repo_url` | `string` | `""` | No | Git repo URL for ApplicationSet source |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `argocd_namespace` | Namespace where ArgoCD is deployed |
| `argocd_release_name` | ArgoCD Helm release name |
| `argocd_controller_role_arn` | IRSA role ARN for the ArgoCD application controller |

## Dependencies

- **eks-cluster**: `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `oidc_provider_arn`, `oidc_provider`
- **midway-auth** (optional): `acm_certificate_arn`, `cognito_user_pool_arn`, `cognito_app_client_ids`, `cognito_user_pool_domain`
- Required providers: `hashicorp/aws ~> 6.0`, `hashicorp/helm >= 2.0`, `hashicorp/kubernetes >= 2.0`
