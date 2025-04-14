# Get current AWS identity
data "aws_caller_identity" "current" {}

# Get existing EKS cluster and its auth
data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.eks_cluster_name
}

# Provider: Kubernetes
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

# Create Namespace if not already present (optional but recommended)
resource "kubernetes_namespace" "harness_delegate_ns" {
  metadata {
    name = "harness-delegate-ng"
  }
}

# Create aws-logging configmap (Fargate expects this)
resource "kubernetes_config_map" "aws_logging" {
  metadata {
    name      = "aws-logging"
    namespace = kubernetes_namespace.harness_delegate_ns.metadata[0].name  # safer than hardcoding
  }

  data = {
    logLevel      = "INFO"
    logStreamName = "terraform-delegate"
  }

  depends_on = [kubernetes_namespace.harness_delegate_ns]
}

# Provider: Helm (used by Harness Delegate module)
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    token                  = data.aws_eks_cluster_auth.eks.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  }
}

# Harness Delegate Module with resource requests and limits
module "delegate" {
  source            = "harness/harness-delegate/kubernetes"
  version           = "0.1.8"

  account_id        = "_Ci0EyZJTDmD1Kc1t_OA_A"
  delegate_token    = "ZDUwMDU5ODE0OGY0M2QyMGVhZjhlNjY4YzIwOThiNTM="
  delegate_name     = "terraform-delegate"
  deploy_mode       = "KUBERNETES"
  namespace         = kubernetes_namespace.harness_delegate_ns.metadata[0].name
  manager_endpoint  = "https://app.harness.io"
  delegate_image    = "us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:25.03.85504"
  replicas          = 1
  upgrader_enabled  = true

  # Add the resource requests and limits
  resources = {
    requests = {
      cpu    = "0.5"    # Request 0.5 CPU
      memory = "1Gi"    # Request 1Gi memory
    }
    limits = {
      cpu    = "1"      # Limit to 1 CPU
      memory = "2Gi"    # Limit to 2Gi memory
    }
  }

  depends_on = [
    kubernetes_config_map.aws_logging
  ]
}
