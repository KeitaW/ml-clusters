locals {
  aws_region         = "us-west-2"
  availability_zones = ["us-west-2a", "us-west-2b"]
  vpc_cidr           = "10.1.0.0/16"
  private_subnet_cidrs = ["10.1.0.0/18", "10.1.64.0/18"]
  public_subnet_cidrs  = ["10.1.128.0/24", "10.1.129.0/24"]
}
