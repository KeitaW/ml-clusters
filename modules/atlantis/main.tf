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
    atlantisUrl  = "https://${var.atlantis_hostname}"
    service = {
      type = "ClusterIP"
    }
    volumeClaim = {
      enabled          = true
      dataStorage      = "10Gi"
      storageClassName = "gp2"
    }
    ingress = {
      enabled = false
    }
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = ""
      }
    }
    loadEnvFromSecrets = ["atlantis-github-credentials"]
    repoConfig = yamlencode({
      repos = [{
        id                     = "/.*/"
        allowed_overrides      = ["workflow"]
        allow_custom_workflows = true
      }]
    })
    initContainers = [{
      name  = "install-terragrunt"
      image = "alpine:3.21"
      command = ["sh", "-c", join(" && ", [
        "wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${var.terragrunt_version}/terragrunt_linux_amd64 -O /extra-bin/terragrunt",
        "chmod +x /extra-bin/terragrunt",
      ])]
      volumeMounts = [{
        name      = "extra-bin"
        mountPath = "/extra-bin"
      }]
    }]
    extraVolumes = [{
      name     = "extra-bin"
      emptyDir = {}
    }]
    extraVolumeMounts = [{
      name      = "extra-bin"
      mountPath = "/extra-bin"
    }]
  })]

  depends_on = [kubernetes_secret_v1.atlantis_github]
}

# Terraform-managed webhook ingress (unauthenticated - GitHub webhooks must bypass Cognito)
resource "kubernetes_ingress_v1" "atlantis_webhook" {
  count = var.enable_cognito_auth ? 1 : 0

  metadata {
    name      = "atlantis-webhook"
    namespace = kubernetes_namespace_v1.atlantis.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/certificate-arn"  = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/group.name"       = var.alb_ingress_group_name
      "alb.ingress.kubernetes.io/group.order"      = "10"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
    }
  }

  spec {
    rule {
      host = var.atlantis_hostname
      http {
        path {
          path      = "/events"
          path_type = "Prefix"
          backend {
            service {
              name = "atlantis"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.atlantis]
}

# Separate Ingress for authenticated catch-all path (Cognito auth on all non-webhook paths)
resource "kubernetes_ingress_v1" "atlantis_authenticated" {
  count = var.enable_cognito_auth ? 1 : 0

  metadata {
    name      = "atlantis-authenticated"
    namespace = kubernetes_namespace_v1.atlantis.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                                = "alb"
      "alb.ingress.kubernetes.io/scheme"                           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"                     = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/certificate-arn"                  = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/group.name"                       = var.alb_ingress_group_name
      "alb.ingress.kubernetes.io/group.order"                      = "20"
      "alb.ingress.kubernetes.io/healthcheck-path"                 = "/healthz"
      "alb.ingress.kubernetes.io/auth-type"                        = "cognito"
      "alb.ingress.kubernetes.io/auth-idp-cognito"                 = jsonencode({
        UserPoolArn      = var.cognito_user_pool_arn
        UserPoolClientId = var.cognito_app_client_id
        UserPoolDomain   = var.cognito_user_pool_domain
      })
      "alb.ingress.kubernetes.io/auth-on-unauthenticated-request"  = "authenticate"
      "external-dns.alpha.kubernetes.io/hostname"                   = var.atlantis_hostname
    }
  }

  spec {
    rule {
      host = var.atlantis_hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "atlantis"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.atlantis]
}
