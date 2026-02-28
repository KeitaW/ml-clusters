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
    dataStorage = "10Gi"
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
  })]
}
