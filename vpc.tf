  module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

   providers = {
    aws = aws.ap-northeast-2
   }

  name = var.cluster_name
  cidr = "10.194.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnets  = ["10.194.0.0/24", "10.194.1.0/24"]
  private_subnets = ["10.194.100.0/24", "10.194.101.0/24"]

  enable_nat_gateway     = true

  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/simon-test" = "owned"  # 클러스터 이름 통일
    "kubernetes.io/role/elb"           = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/simon-test"     = "owned"  # 클러스터 이름 통일
    "kubernetes.io/role/internal-elb"      = "1"
  }

}

