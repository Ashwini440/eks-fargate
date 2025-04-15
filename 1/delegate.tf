# Get current AWS identity
data "aws_caller_identity" "current" {}

# Get existing EKS cluster and its auth
data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.eks_cluster_name
}

# Kubernetes Provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

# Helm Provider
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    token                  = data.aws_eks_cluster_auth.eks.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  }
}



# ConfigMap: aws-logging (required by Fargate)
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

# Secret: Upgrader token
resource "kubernetes_secret" "upgrader_token" {
  metadata {
    name      = "terraform-delegate-upgrader-token"
    namespace = kubernetes_namespace.harness_delegate_ns.metadata[0].name

    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }

    annotations = {
      "meta.helm.sh/release-name"      = "terraform-delegate"
      "meta.helm.sh/release-namespace" = "harness-delegate-ng"
    }
  }

  data = {
    UPGRADER_TOKEN = base64encode("ZDUwMDU5ODE0OGY0M2QyMGVhZjhlNjY4YzIwOThiNTM=")  # already base64-encoded
  }

  type = "Opaque"

  }

# ConfigMap: Observability config (example)
resource "kubernetes_config_map" "observability_config" {
  metadata {
    name      = "observability-config"
    namespace = kubernetes_namespace.observability_ns.metadata[0].name
  }

  data = {
    telemetry_enabled = "true"
    log_level         = "DEBUG"
  }

  depends_on = [kubernetes_namespace.observability_ns]
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
