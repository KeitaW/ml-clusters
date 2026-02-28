mock_provider "aws" {}

variables {
  account_name         = "test"
  aws_region           = "us-east-1"
  vpc_cidr             = "10.99.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs = ["10.99.0.0/18", "10.99.64.0/18"]
  public_subnet_cidrs  = ["10.99.128.0/24", "10.99.129.0/24"]
  is_production        = false
}

run "efa_security_group" {
  command = plan

  assert {
    condition     = aws_security_group.efa.name == "ml-efa-test-us-east-1"
    error_message = "EFA security group name should follow ml-efa-{account}-{region} convention"
  }

  assert {
    condition     = aws_security_group.efa.description == "EFA security group for ML training - all traffic between members"
    error_message = "EFA security group should have descriptive text"
  }
}

run "placement_groups_per_az" {
  command = plan

  assert {
    condition     = length(aws_placement_group.gpu) == 2
    error_message = "Should create one placement group per AZ (2 AZs = 2 groups)"
  }

  assert {
    condition     = aws_placement_group.gpu["us-east-1a"].strategy == "cluster"
    error_message = "Placement groups should use cluster strategy for GPU training"
  }

  assert {
    condition     = aws_placement_group.gpu["us-east-1a"].name == "ml-gpu-cluster-us-east-1a"
    error_message = "Placement group name should include AZ identifier"
  }

  assert {
    condition     = aws_placement_group.gpu["us-east-1b"].name == "ml-gpu-cluster-us-east-1b"
    error_message = "Each AZ should get its own named placement group"
  }
}

run "s3_gateway_endpoint" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway"
    error_message = "S3 endpoint should be Gateway type (no cost, high throughput)"
  }

  assert {
    condition     = aws_vpc_endpoint.s3.service_name == "com.amazonaws.us-east-1.s3"
    error_message = "S3 endpoint service name should match the region"
  }
}

run "ecr_interface_endpoints" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.ecr_api.vpc_endpoint_type == "Interface"
    error_message = "ECR API endpoint should be Interface type"
  }

  assert {
    condition     = aws_vpc_endpoint.ecr_api.private_dns_enabled == true
    error_message = "ECR API endpoint should have private DNS for transparent access"
  }

  assert {
    condition     = aws_vpc_endpoint.ecr_dkr.vpc_endpoint_type == "Interface"
    error_message = "ECR DKR endpoint should be Interface type"
  }

  assert {
    condition     = aws_vpc_endpoint.ecr_dkr.private_dns_enabled == true
    error_message = "ECR DKR endpoint should have private DNS for transparent access"
  }
}

run "vpc_endpoint_security_group" {
  command = plan

  assert {
    condition     = aws_security_group.vpc_endpoints.name == "ml-vpc-endpoints-test-us-east-1"
    error_message = "VPC endpoint security group name should follow convention"
  }
}

run "three_az_deployment" {
  command = plan

  variables {
    availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
    private_subnet_cidrs = ["10.99.0.0/18", "10.99.64.0/18", "10.99.128.0/18"]
    public_subnet_cidrs  = ["10.99.192.0/24", "10.99.193.0/24", "10.99.194.0/24"]
  }

  assert {
    condition     = length(aws_placement_group.gpu) == 3
    error_message = "Should scale placement groups to match 3 AZs"
  }
}
