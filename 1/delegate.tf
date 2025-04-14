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

# Create Namespace
resource "kubernetes_namespace" "harness_delegate_ns" {
  metadata {
    name = "harness-delegate-ng"
  }
}

# aws-logging ConfigMap (required by Fargate)
resource "kubernetes_config_map" "aws_logging" {
  metadata {
    name      = "aws-logging"
    namespace = kubernetes_namespace.harness_delegate_ns.metadata[0].name
  }

  data = {
    logLevel      = "INFO"
    logStreamName = "terraform-delegate"
  }

  depends_on = [kubernetes_namespace.harness_delegate_ns]
}

# Update existing secret or create a new one with Helm-managed metadata
resource "kubernetes_secret" "upgrader_token" {
  metadata {
    name      = "terraform-delegate-upgrader-token"
    namespace = kubernetes_namespace.harness_delegate_ns.metadata[0].name

    # Add Helm-managed labels and annotations
    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }

    annotations = {
      "meta.helm.sh/release-name"      = "terraform-delegate"
      "meta.helm.sh/release-namespace" = "harness-delegate-ng"
    }
  }

  data = {
    UPGRADER_TOKEN = base64encode("ZDUwMDU5ODE0OGY0M2QyMGVhZjhlNjY4YzIwOThiNTM=")  # 👈 Use the decoded token here
  }

  type = "Opaque"
}

# Provider: Helm
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    token                  = data.aws_eks_cluster_auth.eks.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  }
}

# Harness Delegate Module
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

  values = <<-EOT
  resources:
    requests:
      cpu: "0.5"
      memory: "1Gi"
    limits:
      cpu: "1"
      memory: "2Gi"

  extraVolumes:
    - name: aws-logging
      configMap:
        name: aws-logging
    - name: config-volume
      configMap:
        name: terraform-delegate-upgrader-config
    - name: upgrader-token-secret
      secret:
        secretName: terraform-delegate-upgrader-token

  extraVolumeMounts:
    - name: aws-logging
      mountPath: /etc/aws-logging
      readOnly: true
    - name: config-volume
      mountPath: /etc/config
      readOnly: true
    - name: upgrader-token-secret
      mountPath: /etc/upgrader-token
      readOnly: true

  env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: aws-logging
          key: logLevel
    - name: LOG_STREAM_NAME
      valueFrom:
        configMapKeyRef:
          name: aws-logging
          key: logStreamName
    - name: UPGRADER_TOKEN
      valueFrom:
        secretKeyRef:
          name: terraform-delegate-upgrader-token
          key: UPGRADER_TOKEN
  EOT

  depends_on = [
    kubernetes_namespace.harness_delegate_ns,
    kubernetes_config_map.aws_logging,
    kubernetes_secret.upgrader_token
  ]
}

# OPTIONAL: If you want to extract the actual token from the secret
output "upgrader_token_decoded" {
  value     = base64decode(kubernetes_secret.upgrader_token.data["UPGRADER_TOKEN"])
  sensitive = true
}
