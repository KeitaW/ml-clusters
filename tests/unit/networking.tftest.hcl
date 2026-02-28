provider "aws" {
  region = "us-east-1"
}

variables {
  account_name         = "test"
  aws_region           = "us-east-1"
  vpc_cidr             = "10.99.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs = ["10.99.0.0/18", "10.99.64.0/18"]
  public_subnet_cidrs  = ["10.99.128.0/24", "10.99.129.0/24"]
  is_production        = false
}

run "vpc_created" {
  command = plan

  assert {
    condition     = module.vpc.vpc_id != ""
    error_message = "VPC should be created"
  }
}

run "efa_security_group_created" {
  command = plan

  assert {
    condition     = aws_security_group.efa.name == "ml-efa-test-us-east-1"
    error_message = "EFA security group should have correct name"
  }
}

run "placement_groups_per_az" {
  command = plan

  assert {
    condition     = length(aws_placement_group.gpu) == 2
    error_message = "Should create one placement group per AZ"
  }
}
