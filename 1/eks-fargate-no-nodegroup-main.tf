
resource "aws_eks_fargate_profile" "example" {
  cluster_name           = aws_eks_cluster.eks.name
  fargate_profile_name   = "example-fargate-profile"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn

  subnet_ids = [
    data.aws_subnet.private1.id,
    data.aws_subnet.private2.id
  ]

  #selector {
  #  namespace = "default"
 # }
selector {
  namespace = "harness-delegate-ng"
}

  depends_on = [aws_eks_cluster.eks]
}

# IAM Role for Fargate Pod Execution
resource "aws_iam_role" "fargate_pod_execution" {
  name = "eks-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_attachment" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Get the default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
# Fetch private subnet 1
data "aws_subnet" "private1" {
  filter {
    name   = "cidr-block"
    values = ["172.31.64.0/20"]
  }
}

# Fetch private subnet 2
data "aws_subnet" "private2" {
  filter {
    name   = "cidr-block"
    values = ["172.31.80.0/24"]
  }
}


data "aws_security_group" "default" {
  filter {
    name   = "group-name"
    values = ["default"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = var.eks_cluster_role

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "eks" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids             = data.aws_subnets.default.ids
    endpoint_public_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_policy]
}
