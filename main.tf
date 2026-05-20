resource "aws_iam_role_policy_attachment" "additional" {
  for_each = module.eks.eks_managed_node_groups

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
  role       = each.value.iam_role_name
}



module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "21.20.0"

  compute_config = {
   enabled = false
  }
  endpoint_public_access = true

  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  name                    = "simon-test"
  kubernetes_version                  = "1.35"
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  control_plane_subnet_ids        = module.vpc.private_subnets


  # 애드온 설정
   addons = {
    coredns                = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy             = {}
    vpc-cni                = {
      before_compute = true
    }
  }

  providers = {
    aws = aws.ap-northeast-2
  }






  eks_managed_node_groups = {
    one = {
      name          = "node-group-1"
      ami_type = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]
      min_size      = 1
      max_size      = 3
      desired_size  = 2
    }
    two = {
      name          = "node-group-2"
      ami_type = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]
      min_size      = 1
      max_size      = 2
      desired_size  = 1
    }
  }

  enable_cluster_creator_admin_permissions = true


}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "example" {
  name               = "eks-cluster-example"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.example.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.example.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.example.name
}






