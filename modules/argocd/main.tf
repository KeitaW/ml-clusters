# Configure providers using cluster details
provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

# ArgoCD namespace
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

# ArgoCD Helm release
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode({
    server = {
      service = {
        type = "LoadBalancer"
      }
    }
    configs = {
      params = {
        "server.insecure" = true
      }
    }
  })]
}

# Hub cluster self-registration as a secret with GitOps Bridge annotations
resource "kubernetes_secret_v1" "hub_cluster" {
  metadata {
    name      = "hub-cluster"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
    annotations = {
      "cluster_name" = var.cluster_name
      "environment"  = "hub"
    }
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
  }

  depends_on = [helm_release.argocd]
}

# Spoke cluster registration
resource "kubernetes_secret_v1" "spoke_clusters" {
  for_each = var.spoke_clusters

  metadata {
    name      = each.key
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
    annotations = {
      "cluster_name" = each.value.name
      "environment"  = "spoke"
    }
  }

  data = {
    name   = each.value.name
    server = each.value.server
    config = jsonencode({
      tlsClientConfig = {
        caData = each.value.ca_data
      }
    })
  }

  depends_on = [helm_release.argocd]
}
