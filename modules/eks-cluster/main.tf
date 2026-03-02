module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  authentication_mode = var.authentication_mode

  # Allow public access for initial setup, restrict in production
  endpoint_public_access = true

  # EKS managed add-ons (day-0 critical)
  addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {}
    vpc-cni = {
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  # System node group only - GPU nodes managed by Karpenter
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.xlarge"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
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

resource "aws_iam_role" "ebs_csi" {
  name               = "AmazonEKS_EBS_CSI_DriverRole"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Karpenter IAM resources via the EKS module's Karpenter submodule
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.15"

  cluster_name = module.eks.cluster_name

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}
