# eks-cluster

EKS cluster with managed add-ons, Karpenter, and IRSA roles for ML workloads.

## Overview

Provisions an EKS cluster using the community module with a managed system node group, core add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI, Pod Identity), and Karpenter for autoscaling GPU and CPU nodes. Conditionally creates IRSA roles for ALB Controller, External-DNS, ADOT Collector, Ray, and OSMO workloads. Supports HyperPod EKS integration via CloudWatch Observability and Task Governance add-ons.

## Resources Created

- EKS cluster with managed node group "system" (2x m5.xlarge)
- EKS add-ons: CoreDNS, kube-proxy, Pod Identity Agent, VPC CNI, EBS CSI Driver
- Karpenter IAM roles, SQS interruption queue, and instance profile
- EBS CSI Driver IRSA role
- ALB Controller IRSA role and policy
- External-DNS IRSA role (when `route53_zone_id` is set)
- ADOT Collector IRSA role (when `amp_workspace_arn` is set)
- Ray cluster IRSA role (when `ray_s3_bucket_arns` is non-empty)
- OSMO IRSA role with S3 + ECR access (when `osmo_s3_bucket_arns` is non-empty)
- ArgoCD access entries for cross-account hub (when `argocd_access_role_arns` is set)
- CloudWatch Observability add-on (when `enable_cloudwatch_observability` is true)
- HyperPod Task Governance add-on (when `enable_hyperpod_task_governance` is true)

## Usage

```hcl
# live/_envcommon/eks-cluster.hcl
terraform {
  source = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/../modules/eks-cluster"
}

inputs = {
  cluster_name        = "ml-cluster-main-us-east-1"
  aws_region          = "us-east-1"
  vpc_id              = dependency.networking.outputs.vpc_id
  private_subnet_ids  = dependency.networking.outputs.private_subnet_ids
  efa_security_group_id = dependency.networking.outputs.efa_security_group_id
  route53_zone_id     = dependency.midway_auth.outputs.route53_zone_id
  amp_workspace_arn   = dependency.monitoring.outputs.amp_workspace_arn
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `cluster_name` | `string` | — | Yes | Name of the EKS cluster |
| `cluster_version` | `string` | `"1.32"` | No | Kubernetes version |
| `aws_region` | `string` | — | Yes | AWS region |
| `vpc_id` | `string` | — | Yes | VPC ID |
| `private_subnet_ids` | `list(string)` | — | Yes | Private subnet IDs |
| `efa_security_group_id` | `string` | `""` | No | EFA security group ID |
| `authentication_mode` | `string` | `"API_AND_CONFIG_MAP"` | No | EKS authentication mode |
| `route53_zone_id` | `string` | `""` | No | Route53 zone ID for External-DNS IRSA |
| `amp_workspace_arn` | `string` | `""` | No | AMP workspace ARN for ADOT IRSA |
| `argocd_access_role_arns` | `list(string)` | `[]` | No | IAM role ARNs for ArgoCD cluster-admin access |
| `cluster_iam_role_use_name_prefix` | `bool` | `true` | No | Use name_prefix for cluster IAM role |
| `karpenter_controller_role_name` | `string` | `""` | No | Override Karpenter controller role name |
| `karpenter_node_role_name` | `string` | `""` | No | Override Karpenter node role name |
| `ray_s3_bucket_arns` | `list(string)` | `[]` | No | S3 bucket ARNs for Ray IRSA |
| `osmo_s3_bucket_arns` | `list(string)` | `[]` | No | S3 bucket ARNs for OSMO IRSA |
| `enable_cloudwatch_observability` | `bool` | `false` | No | Install CloudWatch Observability add-on |
| `enable_hyperpod_task_governance` | `bool` | `false` | No | Install HyperPod Task Governance add-on |
| `tags` | `map(string)` | `{}` | No | Tags |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | Name of the EKS cluster |
| `cluster_endpoint` | EKS API server endpoint |
| `cluster_certificate_authority_data` | Base64-encoded cluster CA certificate |
| `cluster_arn` | ARN of the EKS cluster |
| `cluster_security_group_id` | Cluster security group ID |
| `node_security_group_id` | Node security group ID |
| `oidc_provider_arn` | OIDC provider ARN |
| `oidc_provider` | OIDC provider URL |
| `karpenter_node_role_arn` | Karpenter node IAM role ARN |
| `karpenter_queue_name` | Karpenter SQS interruption queue name |
| `karpenter_instance_profile_name` | Karpenter instance profile name |
| `karpenter_node_role_name` | Karpenter node IAM role name |
| `ebs_csi_role_arn` | EBS CSI driver IRSA role ARN |
| `alb_controller_role_arn` | ALB Controller IRSA role ARN |
| `external_dns_role_arn` | External-DNS IRSA role ARN |
| `adot_role_arn` | ADOT Collector IRSA role ARN |
| `ray_role_arn` | Ray cluster IRSA role ARN |
| `osmo_role_arn` | OSMO IRSA role ARN |
| `aws_region` | AWS region of the cluster |
| `vpc_id` | VPC ID of the cluster |

## Dependencies

- **networking**: `vpc_id`, `private_subnet_ids`, `efa_security_group_id`
- **midway-auth** (optional): `route53_zone_id`
- **monitoring** (optional): `amp_workspace_arn`
- Required providers: `hashicorp/aws ~> 6.0`
- External modules: `terraform-aws-modules/eks/aws ~> 21.15`
