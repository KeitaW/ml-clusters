provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = merge(var.tags, {
    "terraform"   = "true"
    "cluster"     = var.cluster_name
    "test-case"   = "osmo-amr-pipeline"
  })
}

# ---------- VPC ----------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = 1
    "karpenter.sh/discovery/${var.cluster_name}"   = "true"
  }

  tags = local.tags
}

# ---------- EKS ----------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  # System node group for cluster add-ons
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.xlarge"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2

      labels = {
        "node-role" = "system"
      }
    }
  }

  # Karpenter sub-module — creates controller IRSA + node IAM role
  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_caller_identity.current.account_id
  }
  karpenter_node = {
    iam_role_use_name_prefix = false
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}

# ---------- Karpenter Helm ----------

resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.4.0"
  wait             = true
  create_namespace = false

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.eks.karpenter_queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.eks.karpenter_iam_role_arn
        }
      }
    })
  ]

  depends_on = [module.eks]
}

# ---------- GPU Operator ----------

resource "helm_release" "gpu_operator" {
  namespace        = "gpu-operator"
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = "v25.10.1"
  wait             = true
  create_namespace = true

  values = [
    yamlencode({
      driver = {
        enabled = false
      }
      toolkit = {
        enabled = true
      }
      dcgmExporter = {
        enabled = true
      }
      nfd = {
        enabled = true
      }
      migManager = {
        enabled = false
      }
    })
  ]

  depends_on = [module.eks]
}

# ---------- Karpenter NodePool + EC2NodeClass ----------

resource "kubectl_manifest" "gpu_nodepool" {
  yaml_body = templatefile("${path.module}/karpenter/nodepool.yaml", {
    max_gpu_nodes = var.max_gpu_nodes
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "gpu_ec2nodeclass" {
  yaml_body = templatefile("${path.module}/karpenter/ec2nodeclass.yaml", {
    cluster_name = var.cluster_name
    node_role    = module.eks.karpenter_node_iam_role_name
  })

  depends_on = [helm_release.karpenter]
}

# ---------- Training NodePool (P-series for stage 6) ----------

resource "kubectl_manifest" "training_nodepool" {
  yaml_body = templatefile("${path.module}/karpenter/nodepool-training.yaml", {
    max_training_gpus      = var.max_training_gpus
    training_instance_type = var.training_instance_type
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "training_ec2nodeclass" {
  yaml_body = templatefile("${path.module}/karpenter/ec2nodeclass-training.yaml", {
    cluster_name = var.cluster_name
    node_role    = module.eks.karpenter_node_iam_role_name
  })

  depends_on = [helm_release.karpenter]
}

# ---------- IRSA Role for Pipeline S3 Access ----------

module "pipeline_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name = "${var.cluster_name}-amr-pipeline-s3"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["isaac-sim:amr-pipeline-sa"]
    }
  }

  role_policy_arns = {
    s3 = aws_iam_policy.pipeline_s3.arn
  }
}

resource "aws_iam_policy" "pipeline_s3" {
  name = "${var.cluster_name}-amr-pipeline-s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
        ]
        Resource = [
          aws_s3_bucket.sdg_output.arn,
          "${aws_s3_bucket.sdg_output.arn}/*",
        ]
      }
    ]
  })
}

# ---------- S3 Bucket for SDG Output ----------

resource "aws_s3_bucket" "sdg_output" {
  bucket_prefix = "${var.cluster_name}-sdg-"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sdg_output" {
  bucket = aws_s3_bucket.sdg_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "sdg_output" {
  bucket = aws_s3_bucket.sdg_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
