data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}
# Data for AWS EKS Cluster Authentication (for kubectl access)
data "aws_eks_cluster_auth" "eks" {
  name = var.eks_cluster_name
}


provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    token                  = data.aws_eks_cluster_auth.eks.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  }
}




module "delegate" {
  source = "harness/harness-delegate/kubernetes"
  version = "0.1.8"

  account_id = "_Ci0EyZJTDmD1Kc1t_OA_A"
  delegate_token = "ZDUwMDU5ODE0OGY0M2QyMGVhZjhlNjY4YzIwOThiNTM="
  delegate_name = "terraform-delegate"
  deploy_mode = "KUBERNETES"
  namespace = "harness-delegate-ng"
  manager_endpoint = "https://app.harness.io"
  delegate_image = "us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:25.03.85504"
  replicas = 1
  upgrader_enabled = true
  depends_on = [aws_eks_cluster.eks]
}
