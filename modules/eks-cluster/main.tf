module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  # Keep name_prefix for cluster-level IAM role (changing it forces cluster replacement)
  # Node group and Karpenter roles use explicit names below for multi-cluster support

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  authentication_mode = var.authentication_mode

  # Allow public access for initial setup, restrict in production
  endpoint_public_access = true

  # EKS managed add-ons — before_compute ensures addons install before node groups
  addons = {
    coredns = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute       = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    aws-ebs-csi-driver = {
      before_compute          = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  # System node group only - GPU nodes managed by Karpenter
  eks_managed_node_groups = {
    system = {
      ami_type                 = "AL2023_x86_64_STANDARD"
      instance_types           = ["m5.xlarge"]
      min_size                 = 2
      max_size                 = 4
      desired_size             = 2
      iam_role_use_name_prefix = false
      use_name_prefix          = false
    }
  }

  # Tag the node security group for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

# IRSA role for the EBS CSI driver addon
data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

locals {
  # Use cluster-name-suffixed IAM names for multi-cluster support
  iam_suffix = var.cluster_name
}

resource "aws_iam_role" "ebs_csi" {
  name               = "EBS-CSI-${local.iam_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# IRSA role for the AWS Load Balancer Controller
data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "ALBController-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
  tags               = var.tags
}

resource "aws_iam_policy" "alb_controller" {
  name        = "ALBControllerPolicy-${var.cluster_name}"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/policies/alb-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# IRSA role for External-DNS (only when route53_zone_id is provided)
data "aws_iam_policy_document" "external_dns_trust" {
  count = var.route53_zone_id != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = var.route53_zone_id != "" ? 1 : 0

  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]
  }
  statement {
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count              = var.route53_zone_id != "" ? 1 : 0
  name               = "ExternalDNS-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust[0].json
  tags               = var.tags
}

resource "aws_iam_policy" "external_dns" {
  count       = var.route53_zone_id != "" ? 1 : 0
  name        = "ExternalDNSPolicy-${var.cluster_name}"
  description = "Allows external-dns to manage Route53 records"
  policy      = data.aws_iam_policy_document.external_dns[0].json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  count      = var.route53_zone_id != "" ? 1 : 0
  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}

# IRSA role for ADOT Collector (only when amp_workspace_arn is provided)
data "aws_iam_policy_document" "adot_trust" {
  count = var.amp_workspace_arn != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:opentelemetry:adot-collector"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "adot" {
  count              = var.amp_workspace_arn != "" ? 1 : 0
  name               = "ADOTCollector-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.adot_trust[0].json
  tags               = var.tags
}

resource "aws_iam_policy" "adot" {
  count = var.amp_workspace_arn != "" ? 1 : 0
  name  = "ADOTCollectorPolicy-${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata",
        ]
        Resource = var.amp_workspace_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "adot" {
  count      = var.amp_workspace_arn != "" ? 1 : 0
  role       = aws_iam_role.adot[0].name
  policy_arn = aws_iam_policy.adot[0].arn
}

# ArgoCD hub access entries
resource "aws_eks_access_entry" "argocd" {
  for_each = toset(var.argocd_access_role_arns)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "argocd" {
  for_each = toset(var.argocd_access_role_arns)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.argocd]
}

# Karpenter IAM resources via the EKS module's Karpenter submodule
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.15"

  cluster_name = module.eks.cluster_name

  # Disable name_prefix to avoid 38-char limit with long cluster names
  iam_role_use_name_prefix      = false
  iam_policy_use_name_prefix    = false
  node_iam_role_use_name_prefix = false

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}
