locals {
  eks_token_args = var.assume_role_arn != "" ? ["eks", "get-token", "--cluster-name", var.cluster_name, "--role-arn", var.assume_role_arn] : ["eks", "get-token", "--cluster-name", var.cluster_name]
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.eks_token_args
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.eks_token_args
  }
}

resource "kubernetes_namespace_v1" "atlantis" {
  metadata {
    name = var.atlantis_namespace
  }
}

resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "atlantis_github" {
  name       = "atlantis/github-credentials"
  kms_key_id = var.kms_key_arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "atlantis_github" {
  secret_id = aws_secretsmanager_secret.atlantis_github.id
  secret_string = jsonencode({
    ATLANTIS_GH_USER           = var.github_user
    ATLANTIS_GH_TOKEN          = var.github_token
    ATLANTIS_GH_WEBHOOK_SECRET = random_password.webhook_secret.result
  })
}

resource "kubernetes_secret_v1" "atlantis_github" {
  metadata {
    name      = "atlantis-github-credentials"
    namespace = kubernetes_namespace_v1.atlantis.metadata[0].name
  }

  data = {
    ATLANTIS_GH_USER           = var.github_user
    ATLANTIS_GH_TOKEN          = var.github_token
    ATLANTIS_GH_WEBHOOK_SECRET = random_password.webhook_secret.result
  }
}

resource "helm_release" "atlantis" {
  name       = "atlantis"
  repository = "https://runatlantis.github.io/helm-charts"
  chart      = "atlantis"
  version    = var.atlantis_chart_version
  namespace  = kubernetes_namespace_v1.atlantis.metadata[0].name

  values = [yamlencode({
    orgAllowlist = join(",", var.atlantis_repo_allowlist)
    service = {
      type = "ClusterIP"
    }
    volumeClaim = {
      enabled          = true
      dataStorage      = "10Gi"
      storageClassName = "gp2"
    }
    ingress = {
      enabled = true
      annotations = {
        "kubernetes.io/ingress.class"            = "alb"
        "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"  = "ip"
        "alb.ingress.kubernetes.io/listen-ports"  = "[{\"HTTPS\":443}]"
      }
      path     = "/events"
      pathType = "Prefix"
    }
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = ""
      }
    }
    loadEnvFromSecrets = ["atlantis-github-credentials"]
  })]

  depends_on = [kubernetes_secret_v1.atlantis_github]
}
