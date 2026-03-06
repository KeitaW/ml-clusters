# parallelcluster

AWS ParallelCluster API and Slurm cluster deployment.

## Overview

Wraps the official `aws-tf/parallelcluster/aws` community module to deploy the ParallelCluster API (one-time per region) and one or more Slurm clusters via CloudFormation. Cluster configurations are templated YAML files with variable substitution for subnet IDs, FSx/EFS filesystem IDs, and capacity reservation IDs.

## Resources Created

- ParallelCluster API CloudFormation stack (when `deploy_pcluster_api` is true)
- One or more ParallelCluster Slurm clusters (via CloudFormation, one per entry in `cluster_configs`)

## Usage

```hcl
# live/_envcommon/parallelcluster.hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//modules/parallelcluster"
}

inputs = {
  region             = "us-east-1"
  deploy_pcluster_api = true
  api_version        = "3.12.0"

  cluster_configs = {
    training = {
      config_path            = "${get_repo_root()}/cluster-configs/parallelcluster/training.yaml"
      head_node_subnet_id    = dependency.networking.outputs.private_subnet_ids[0]
      compute_subnet_id      = dependency.networking.outputs.private_subnet_ids[0]
      fsx_filesystem_id      = dependency.shared_storage.outputs.fsx_filesystem_id
      efs_filesystem_id      = dependency.shared_storage.outputs.efs_filesystem_id
    }
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `region` | `string` | — | Yes | AWS region |
| `deploy_pcluster_api` | `bool` | `true` | No | Deploy the PCluster API stack |
| `api_stack_name` | `string` | `""` | No | Override API stack name |
| `api_version` | `string` | `"3.12.0"` | No | ParallelCluster API version |
| `cluster_configs` | `map(object)` | — | Yes | Map of cluster configurations |

### `cluster_configs` object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `config_path` | `string` | Yes | Path to YAML template file |
| `head_node_subnet_id` | `string` | Yes | Subnet ID for the head node |
| `compute_subnet_id` | `string` | Yes | Subnet ID for compute nodes |
| `fsx_filesystem_id` | `string` | Yes | FSx Lustre filesystem ID |
| `efs_filesystem_id` | `string` | Yes | EFS filesystem ID |
| `capacity_reservation_id` | `string` | No | EC2 Capacity Reservation ID |

## Outputs

| Name | Description |
|------|-------------|
| `pcluster_api_stack_name` | PCluster API CloudFormation stack name |
| `clusters` | Map of managed ParallelCluster clusters |

## Dependencies

- **networking**: subnet IDs via `cluster_configs`
- **shared-storage**: `fsx_filesystem_id`, `efs_filesystem_id`
- Required providers: `hashicorp/aws >= 5.0`, `aws-tf/aws-parallelcluster ~> 1.1`
- Note: The PCluster API CloudFormation stack must exist before the provider can initialize
