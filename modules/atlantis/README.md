# atlantis

Atlantis deployment for PR-based Terraform/Terragrunt workflow.

## Overview

Deploys Atlantis via Helm on EKS with Pod Identity for AWS authentication and a Terragrunt init container. Stores GitHub credentials in both Secrets Manager (KMS-encrypted) and a Kubernetes secret. Supports dual ALB ingress: an unauthenticated path for GitHub webhooks (`/events`) and a Cognito-authenticated path for the UI. The Atlantis pod can assume TerraformExecutionRole in multiple accounts for cross-account plan/apply.

## Resources Created

- Atlantis Helm release (ClusterIP, 10Gi PVC, Terragrunt init container)
- Atlantis namespace
- EKS Pod Identity IAM role with AssumeRole to TerraformExecutionRole ARNs and S3 state access
- EKS Pod Identity association for the `atlantis` service account
- Secrets Manager secret with GitHub credentials (user, token, webhook secret)
- Kubernetes secret with GitHub credentials
- Random webhook secret (32 characters)
- Dual ALB ingress: webhook path (unauthenticated) + UI (Cognito-authenticated) (when `enable_cognito_auth` is true)

## Usage

```hcl
# live/main-account/us-east-1/atlantis/terragrunt.hcl
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/atlantis"
}

inputs = {
  cluster_name           = dependency.eks.outputs.cluster_name
  cluster_endpoint       = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.eks.outputs.cluster_certificate_authority_data

  github_user  = "KeitaW"
  github_token = get_env("GITHUB_PERSONAL_ACCESS_TOKEN")
  terraform_execution_role_arns = [
    "arn:aws:iam::483026362307:role/TerraformExecutionRole",
    "arn:aws:iam::159553542841:role/TerraformExecutionRole",
  ]
  tfstate_bucket_name = "ml-clusters-tfstate-483026362307"
  kms_key_arn         = dependency.iam.outputs.kms_key_arn

  enable_cognito_auth = true
  atlantis_hostname   = "atlantis.mlkeita.people.aws.dev"
  acm_certificate_arn = dependency.midway_auth.outputs.acm_certificate_arn
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `cluster_name` | `string` | — | Yes | EKS cluster name |
| `cluster_endpoint` | `string` | — | Yes | EKS cluster endpoint URL |
| `cluster_ca_certificate` | `string` | — | Yes | Base64-encoded cluster CA certificate |
| `github_user` | `string` (sensitive) | — | Yes | GitHub username |
| `github_token` | `string` (sensitive) | — | Yes | GitHub PAT |
| `terraform_execution_role_arns` | `list(string)` | — | Yes | TerraformExecutionRole ARNs for cross-account access |
| `tfstate_bucket_name` | `string` | — | Yes | S3 bucket for Terraform state |
| `atlantis_chart_version` | `string` | `"5.12.0"` | No | Atlantis Helm chart version |
| `terragrunt_version` | `string` | `"0.99.4"` | No | Terragrunt version for init container |
| `atlantis_namespace` | `string` | `"atlantis"` | No | Kubernetes namespace |
| `github_org` | `string` | `""` | No | GitHub organization |
| `github_repo` | `string` | `""` | No | GitHub repository |
| `atlantis_repo_allowlist` | `list(string)` | `["github.com/KeitaW/ml-clusters"]` | No | Allowed repositories |
| `assume_role_arn` | `string` | `""` | No | IAM role ARN for cluster auth |
| `kms_key_arn` | `string` | `""` | No | KMS key ARN for Secrets Manager encryption |
| `enable_cognito_auth` | `bool` | `false` | No | Enable Cognito ALB authentication |
| `acm_certificate_arn` | `string` | `""` | No | ACM certificate ARN |
| `atlantis_hostname` | `string` | `""` | No | Hostname for Atlantis |
| `alb_ingress_group_name` | `string` | `"ml-cluster-services"` | No | Shared ALB IngressGroup name |
| `cognito_user_pool_arn` | `string` | `""` | No | Cognito User Pool ARN |
| `cognito_app_client_id` | `string` | `""` | No | Cognito App Client ID |
| `cognito_user_pool_domain` | `string` | `""` | No | Cognito User Pool domain |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `atlantis_namespace` | Namespace where Atlantis is deployed |
| `atlantis_release_name` | Atlantis Helm release name |
| `atlantis_secrets_manager_arn` | Secrets Manager secret ARN |
| `atlantis_webhook_secret` | GitHub webhook secret (sensitive) |
| `atlantis_pod_identity_role_arn` | Pod Identity IAM role ARN |

## Dependencies

- **eks-cluster**: `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`
- **iam**: `kms_key_arn`, `terraform_execution_role_arn`
- **midway-auth** (optional): `acm_certificate_arn`, `cognito_user_pool_arn`, `cognito_app_client_ids`, `cognito_user_pool_domain`
- Required providers: `hashicorp/aws ~> 6.0`, `hashicorp/helm >= 2.0`, `hashicorp/kubernetes >= 2.0`, `hashicorp/random >= 3.0`
