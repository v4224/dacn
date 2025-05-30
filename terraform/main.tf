module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name    = "book-reviews-vpc"
  cidr    = "10.0.0.0/16"

  azs             = ["ap-southeast-1a", "ap-southeast-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "book-reviews-cluster"
  cluster_version = "1.27"
  subnets         = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  node_groups = {
    default = {
      desired_capacity = 3
      max_capacity     = 4
      min_capacity     = 2
      instance_type    = "t3.medium"
    }
  }
}
