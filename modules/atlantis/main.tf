data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.cluster.token
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

###############################################################################
# Pod Identity — gives Atlantis pod AWS credentials to run Terraform
###############################################################################

data "aws_iam_policy_document" "atlantis_pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

resource "aws_iam_role" "atlantis_pod_identity" {
  name               = "AtlantisPodIdentity-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.atlantis_pod_identity_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "atlantis_terraform" {
  statement {
    sid       = "AssumeTerraformExecutionRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [var.terraform_execution_role_arn]
  }

  # S3 backend access — the backend config does not use assume_role,
  # so the Pod Identity role needs direct access to the state bucket.
  statement {
    sid    = "TfStateS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket_name}",
      "arn:aws:s3:::${var.tfstate_bucket_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "atlantis_terraform" {
  name   = "assume-terraform-execution-role"
  role   = aws_iam_role.atlantis_pod_identity.id
  policy = data.aws_iam_policy_document.atlantis_terraform.json
}

resource "aws_eks_pod_identity_association" "atlantis" {
  cluster_name    = var.cluster_name
  namespace       = kubernetes_namespace_v1.atlantis.metadata[0].name
  service_account = "atlantis"
  role_arn        = aws_iam_role.atlantis_pod_identity.arn
  tags            = var.tags
}

###############################################################################
# Helm Release
###############################################################################

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
      create = true
      name   = "atlantis"
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
