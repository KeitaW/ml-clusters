# Lessons Learned: AWS ML Cluster Management Research

## Key Architectural Insights

1. **Three different Terraform providers required**: ParallelCluster (aws-tf/aws-parallelcluster), EKS (hashicorp/aws), HyperPod (hashicorp/awscc). This is a significant complexity driver — the design must handle multi-provider coordination.

2. **ParallelCluster has a unique deployment model**: Requires a serverless API (API Gateway + Lambda) deployed via CloudFormation before Terraform can manage clusters. This is a bootstrapping dependency that must be handled in the dependency graph.

3. **HyperPod has no official Terraform module**: Unlike ParallelCluster (aws-tf/parallelcluster/aws) and EKS (terraform-aws-modules/eks/aws), HyperPod only has the raw AWSCC resource. A custom module is needed.

4. **EFA security group rule is universal**: All three cluster types need the same self-referencing all-traffic security group rule for EFA. This is a natural shared component.

5. **Storage mounting differs per cluster type**: FSx Lustre is mounted via YAML config (ParallelCluster), CSI driver + PV/PVC (EKS), and instance storage config (HyperPod). The storage itself can be shared, but the mounting mechanism is cluster-specific.

6. **GitOps has two layers**: Terraform GitOps (Atlantis for PR-based plan/apply) and Kubernetes GitOps (ArgoCD for workload management). These are complementary, not competing.

7. **S3 native locking replaces DynamoDB** (Terraform 1.10+). DynamoDB-based locking is deprecated. Use `use_lockfile = true`.

8. **EKS Pod Identity replaces IRSA** (terraform-aws-eks v21.x). IRSA support removed from module.

9. **terraform-aws-modules/eks/aws v21.15.1 requires AWS provider >= 6.28** (not v5.x). This is a breaking change from earlier EKS module versions. The hashicorp/aws provider version must match.

10. **S3 replication only covers new objects**: Existing objects require a one-time S3 Batch Replication job. This is a common gotcha when setting up hub-and-spoke replication.

11. **SageMaker Training Plans cannot be shared cross-account**: Each plan must be purchased and consumed in the same account. This affects multi-account capacity management workflows.

12. **HyperPod EKS has strict prerequisite validation**: EKS version, auth mode (must be API or API_AND_CONFIG_MAP), VPC CNI version, and Pod Identity Agent add-on must all be in supported ranges. Drift in any of these can break HyperPod operations.

## Version Sensitivity Warnings

- ParallelCluster Terraform support requires v3.8.0+ minimum
- HyperPod AWSCC support requires provider v1.25.0+
- EKS EFA requires VPC CNI v1.18.4+
- HyperPod subnet sizing: 32 IPs/instance (Slurm) vs 81 IPs/instance (EKS) — plan CIDRs carefully
- HCP Terraform free tier EOL: March 31, 2026

## Common Misconceptions

- ParallelCluster is NOT in the hashicorp/aws provider (it's in a separate aws-tf provider)
- AWS PCS (Parallel Computing Service) is a DIFFERENT service from ParallelCluster
- EKS Blueprints v5 is NOT a consumable module — it's reference patterns
- tfsec is deprecated — use Trivy instead
