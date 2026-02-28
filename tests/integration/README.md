# Integration Tests

Integration tests use [Terratest](https://terratest.gruntwork.io/) to validate infrastructure provisioning against real AWS accounts.

## Unit Tests

Unit tests live alongside each module using Terraform's native test framework (`*.tftest.hcl`).
They use `mock_provider` to run without AWS credentials.

```bash
# Run tests for a single module
cd modules/networking && terraform test

# Run all module tests
for dir in modules/*/; do
  echo "=== Testing $dir ==="
  (cd "$dir" && terraform init -backend=false && terraform test) || exit 1
done
```

### Tested Modules

| Module | Test File | Key Assertions |
|--------|-----------|----------------|
| networking | `networking.tftest.hcl` | EFA SG naming, placement groups per AZ, VPC endpoint types |
| s3-data-bucket | `s3.tftest.hcl` | Versioning, public access block, SSE-KMS, lifecycle rules |
| iam | `iam.tftest.hcl` | KMS key config, conditional role creation, role naming |
| s3-replication | `s3_replication.tftest.hcl` | Rule count, prefix filtering, delete marker replication |
| shared-storage | `shared_storage.tftest.hcl` | FSx PERSISTENT_2/LZ4, EFS encryption/elastic, mount targets, access point |
| monitoring | `monitoring.tftest.hcl` | AMP/AMG naming, IP exhaustion alarms per subnet, replication lag threshold |
| hyperpod | `hyperpod.tftest.hcl` | Slurm/EKS orchestrator, precondition validation, node recovery |

## Integration Test Strategy

1. **VPC + Networking**: Deploy a VPC with test CIDRs, validate subnet creation, NAT gateways, and VPC endpoints
2. **S3 + Replication**: Create source and destination buckets, upload test objects, verify cross-region replication
3. **EKS**: Deploy a minimal EKS cluster, verify add-ons are active, run a test pod
4. **Storage**: Create FSx and EFS filesystems, verify mount targets and DRA configuration

## Prerequisites

- AWS credentials with AdministratorAccess in a test account
- Go 1.21+
- Terratest: `go get github.com/gruntwork-io/terratest`

## Running

```bash
cd tests/integration
go test -v -timeout 60m ./...
```

## Cost Warning

Integration tests create real AWS resources. Estimated cost per full run: ~$50-100.
Always run `terraform destroy` after tests complete (Terratest handles this automatically).
