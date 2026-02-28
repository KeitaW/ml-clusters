# Design Doc Plan: AWS ML Cluster Management with GitOps + Terraform

## Status: COMPLETE

## Research Phase: COMPLETE
- All 7 research streams completed (see tasks/research-report.md)
- Multi-account, S3 replication, capacity blocks, training plans researched

## Design Doc Sections to Write

1. [x] Context and Problem Statement
2. [x] Goals and Non-Goals
3. [x] Background and Prior Art
4. [x] Proposed Design
   - [x] Architecture Overview (system diagram)
   - [x] Repository Structure (Terragrunt monorepo)
   - [x] Layer 1: Shared Infrastructure (VPC, storage, IAM, KMS)
   - [x] Layer 2: Cluster Orchestration (ParallelCluster, EKS, HyperPod)
   - [x] Layer 3: GitOps (Atlantis for TF, ArgoCD for K8s)
   - [x] Layer 4: Data Distribution (S3 hub-and-spoke replication)
   - [x] Layer 5: Capacity Management (Capacity Blocks + Training Plans skills)
   - [x] Layer 6: Observability
5. [x] Alternatives Considered
6. [x] Operational Considerations
7. [x] Security and Cost
8. [x] Open Questions
9. [x] References

## Key Design Decisions to Make
- VPC CIDR allocation scheme across 2 accounts × N regions
- When to use ParallelCluster vs EKS vs HyperPod (decision framework)
- Atlantis deployment (where? EKS? EC2?)
- ArgoCD hub-spoke vs per-cluster

## Codex Review: COMPLETE
- 9 findings accepted and incorporated into design doc
- 1 finding rejected (HyperPod Slurm awscc support — verified as supported)
- Critical fix: AWS provider version bumped from v5.x to v6.x (EKS module v21.15.1 requires >= 6.28)
- New sections added: 5.5 (VPC Peering vs TGW), 5.6 (AWS PCS), Appendix (Codex findings)
