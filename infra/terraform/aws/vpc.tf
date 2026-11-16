data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # The AWS cloud provider uses these tags to place Service type=LoadBalancer.
  cluster_subnet_tag = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 private subnets for nodes and pods (VPC CNI gives every pod a VPC IP),
  # /24 public subnets for load balancers and the NAT gateway.
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags  = merge(local.cluster_subnet_tag, { "kubernetes.io/role/elb" = "1" })
  private_subnet_tags = merge(local.cluster_subnet_tag, { "kubernetes.io/role/internal-elb" = "1" })
}
