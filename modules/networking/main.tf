################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "ml-${var.account_name}-${var.aws_region}"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  one_nat_gateway_per_az = var.is_production
  single_nat_gateway     = !var.is_production

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}

################################################################################
# EFA Security Group
################################################################################

resource "aws_security_group" "efa" {
  name        = "ml-efa-${var.account_name}-${var.aws_region}"
  description = "EFA security group for ML training - all traffic between members"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All traffic from self"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  egress {
    description = "All outbound traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

################################################################################
# Placement Groups
################################################################################

resource "aws_placement_group" "gpu" {
  for_each = toset(var.availability_zones)

  name     = "ml-gpu-cluster-${each.value}"
  strategy = "cluster"

  tags = var.tags
}

################################################################################
# VPC Endpoints
################################################################################

# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(var.tags, {
    Name = "ml-${var.account_name}-s3-endpoint"
  })
}

# Security group for interface endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "ml-vpc-endpoints-${var.account_name}-${var.aws_region}"
  description = "Security group for VPC interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.vpc_cidr]
  }

  tags = var.tags
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "ml-${var.account_name}-ecr-api-endpoint"
  })
}

# ECR DKR Interface Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "ml-${var.account_name}-ecr-dkr-endpoint"
  })
}
