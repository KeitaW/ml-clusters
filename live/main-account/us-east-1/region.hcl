locals {
  aws_region         = "us-east-1"
  availability_zones = ["us-east-1a", "us-east-1b"]
  vpc_cidr           = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.0.0/18", "10.0.64.0/18"]
  public_subnet_cidrs  = ["10.0.128.0/24", "10.0.129.0/24"]
}
