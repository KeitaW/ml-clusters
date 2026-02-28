# Root Terragrunt configuration
# All child configs inherit from this file

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_id   = local.account_vars.locals.account_id
  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
}

# S3 remote state with native S3 locking (Terraform 1.10+)
remote_state {
  backend = "s3"
  config = {
    bucket       = "ml-clusters-tfstate-483026362307"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate the AWS provider with assume_role into the target account
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      assume_role {
        role_arn = "arn:aws:iam::${local.account_id}:role/TerraformExecutionRole"
      }

      default_tags {
        tags = {
          ManagedBy   = "terraform"
          Repository  = "ml-clusters"
          Account     = "${local.account_name}"
          Region      = "${local.aws_region}"
        }
      }
    }
  EOF
}

# Note: version constraints are defined in each module's versions.tf.
# Modules requiring additional providers (parallelcluster, hyperpod) have
# their own required_providers blocks.

# Common inputs passed to all modules
inputs = {
  account_id   = local.account_id
  account_name = local.account_name
  aws_region   = local.aws_region
}
