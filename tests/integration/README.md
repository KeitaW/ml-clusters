# Integration Tests

Integration tests use [Terratest](https://terratest.gruntwork.io/) to validate infrastructure provisioning against real AWS accounts.

## Strategy

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
