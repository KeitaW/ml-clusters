# Configure providers using cluster auth token (no aws CLI dependency)
locals {
  spoke_access_role_arns = compact([for k, v in var.spoke_clusters : v.role_arn if v.role_arn != null])
}

data "aws_eks_cluster_auth" "hub" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.hub.token
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.hub.token
}

###############################################################################
# IRSA role for ArgoCD application-controller and server
###############################################################################

data "aws_iam_policy_document" "argocd_controller_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider, "https://", "")}:sub"
      values = [
        "system:serviceaccount:${var.argocd_namespace}:argocd-application-controller",
        "system:serviceaccount:${var.argocd_namespace}:argocd-server",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "argocd_controller_permissions" {
  statement {
    sid       = "EKSDescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(local.spoke_access_role_arns) > 0 ? [1] : []
    content {
      sid       = "AssumeSpokeRoles"
      actions   = ["sts:AssumeRole"]
      resources = local.spoke_access_role_arns
    }
  }
}

resource "aws_iam_role" "argocd_controller" {
  name               = "ArgoCD-Hub-Controller"
  assume_role_policy = data.aws_iam_policy_document.argocd_controller_trust.json
  tags               = var.tags
}

resource "aws_iam_policy" "argocd_controller" {
  name   = "ArgoCD-Hub-Controller-Policy"
  policy = data.aws_iam_policy_document.argocd_controller_permissions.json
}

resource "aws_iam_role_policy_attachment" "argocd_controller" {
  role       = aws_iam_role.argocd_controller.name
  policy_arn = aws_iam_policy.argocd_controller.arn
}

###############################################################################
# ArgoCD namespace and Helm release
###############################################################################

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode({
    controller = {
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.argocd_controller.arn
        }
      }
    }
    server = {
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.argocd_controller.arn
        }
      }
      service = {
        type = "ClusterIP"
      }
      ingress = {
        enabled = var.enable_cognito_auth
        annotations = var.enable_cognito_auth ? {
          "kubernetes.io/ingress.class"                               = "alb"
          "alb.ingress.kubernetes.io/scheme"                          = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"                     = "ip"
          "alb.ingress.kubernetes.io/listen-ports"                    = "[{\"HTTPS\":443}]"
          "alb.ingress.kubernetes.io/certificate-arn"                 = var.acm_certificate_arn
          "alb.ingress.kubernetes.io/group.name"                      = var.alb_ingress_group_name
          "alb.ingress.kubernetes.io/healthcheck-path"                = "/healthz"
          "alb.ingress.kubernetes.io/auth-type"                       = "cognito"
          "alb.ingress.kubernetes.io/auth-idp-cognito" = jsonencode({
            UserPoolArn      = var.cognito_user_pool_arn
            UserPoolClientId = var.cognito_app_client_id
            UserPoolDomain   = var.cognito_user_pool_domain
          })
          "alb.ingress.kubernetes.io/auth-on-unauthenticated-request" = "authenticate"
          "external-dns.alpha.kubernetes.io/hostname"                  = var.argocd_hostname
        } : {}
        hostname = var.argocd_hostname
        path     = "/"
        pathType = "Prefix"
      }
    }
    configs = {
      params = {
        "server.insecure" = true
      }
    }
  })]
}

###############################################################################
# Hub cluster self-registration with GitOps Bridge annotations
###############################################################################

resource "kubernetes_secret_v1" "hub_cluster" {
  metadata {
    name      = "hub-cluster"
    namespace = var.argocd_namespace
    labels = merge(
      {
        "argocd.argoproj.io/secret-type" = "cluster"
      },
      { for k, v in var.hub_annotations : k => v if contains(["enable_karpenter", "enable_external_dns", "enable_adot", "enable_kuberay", "enable_osmo_karpenter", "enable_gpu_operator", "enable_kai_scheduler", "enable_osmo"], k) }
    )
    annotations = merge(
      {
        "cluster_name" = var.cluster_name
        "environment"  = "hub"
      },
      var.hub_annotations
    )
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
  }

  depends_on = [helm_release.argocd]
}

###############################################################################
# Spoke cluster registration with awsAuthConfig
###############################################################################

resource "kubernetes_secret_v1" "spoke_clusters" {
  for_each = var.spoke_clusters

  metadata {
    name      = each.key
    namespace = var.argocd_namespace
    labels = merge(
      {
        "argocd.argoproj.io/secret-type" = "cluster"
      },
      { for k, v in each.value.annotations : k => v if contains(["enable_karpenter", "enable_external_dns", "enable_adot", "enable_kuberay", "enable_osmo_karpenter", "enable_gpu_operator", "enable_kai_scheduler", "enable_osmo"], k) }
    )
    annotations = merge(
      {
        "cluster_name" = each.value.cluster_name
        "environment"  = "spoke"
      },
      each.value.annotations
    )
  }

  data = {
    name   = each.value.name
    server = each.value.server
    config = jsonencode(merge(
      {
        awsAuthConfig = merge(
          { clusterName = each.value.cluster_name },
          each.value.role_arn != null ? { roleARN = each.value.role_arn } : {}
        )
      },
      {
        tlsClientConfig = {
          caData = each.value.ca_data
        }
      }
    ))
  }

  depends_on = [helm_release.argocd]
}

###############################################################################
# Bootstrap Application — deploys per-addon ApplicationSets to hub
###############################################################################

resource "kubernetes_manifest" "bootstrap_app" {
  count = var.enable_applicationset_bootstrap ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "bootstrap"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = "main"
        path           = "gitops/bootstrap"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "ServerSideApply=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
