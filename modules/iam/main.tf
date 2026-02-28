###############################################################################
# Data Sources
###############################################################################

data "aws_caller_identity" "current" {}

###############################################################################
# Shared KMS Key
###############################################################################

data "aws_iam_policy_document" "kms_key_policy" {
  # Root account full access
  statement {
    sid    = "RootAccountFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Cross-account access
  dynamic "statement" {
    for_each = length(var.cross_account_ids) > 0 ? [1] : []
    content {
      sid    = "CrossAccountAccess"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [for id in var.cross_account_ids : "arn:aws:iam::${id}:root"]
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo",
      ]

      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "shared" {
  description             = "Shared KMS key for ml-${var.account_name}-${var.aws_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = var.tags
}

resource "aws_kms_alias" "shared" {
  name          = "alias/ml-${var.account_name}-${var.aws_region}"
  target_key_id = aws_kms_key.shared.key_id
}

###############################################################################
# TerraformExecutionRole
###############################################################################

data "aws_iam_policy_document" "terraform_execution_assume_role" {
  count = var.create_terraform_execution_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "terraform_execution" {
  count = var.create_terraform_execution_role ? 1 : 0

  name               = "TerraformExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.terraform_execution_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "terraform_execution_admin" {
  count = var.create_terraform_execution_role ? 1 : 0

  role       = aws_iam_role.terraform_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

###############################################################################
# ParallelCluster Head Node Role
###############################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  count = var.create_parallelcluster_roles ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "parallelcluster_head_node" {
  count = var.create_parallelcluster_roles ? 1 : 0

  statement {
    sid    = "EC2Access"
    effect = "Allow"

    actions = [
      "ec2:Describe*",
      "ec2:CreateTags",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "S3Access"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CloudFormationAccess"
    effect = "Allow"

    actions = [
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:DescribeStackResources",
      "cloudformation:SignalResource",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "IAMPassRole"
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "parallelcluster_head_node" {
  count = var.create_parallelcluster_roles ? 1 : 0

  name               = "ParallelClusterHeadNodeRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "parallelcluster_head_node_ssm" {
  count = var.create_parallelcluster_roles ? 1 : 0

  role       = aws_iam_role.parallelcluster_head_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "parallelcluster_head_node" {
  count = var.create_parallelcluster_roles ? 1 : 0

  name   = "ParallelClusterHeadNodePolicy"
  role   = aws_iam_role.parallelcluster_head_node[0].id
  policy = data.aws_iam_policy_document.parallelcluster_head_node[0].json
}

###############################################################################
# ParallelCluster Compute Role
###############################################################################

data "aws_iam_policy_document" "parallelcluster_compute" {
  count = var.create_parallelcluster_roles ? 1 : 0

  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"

    actions = [
      "dynamodb:Query",
      "dynamodb:GetItem",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "S3Access"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "EC2Access"
    effect = "Allow"

    actions = [
      "ec2:Describe*",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "parallelcluster_compute" {
  count = var.create_parallelcluster_roles ? 1 : 0

  name               = "ParallelClusterComputeRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "parallelcluster_compute" {
  count = var.create_parallelcluster_roles ? 1 : 0

  name   = "ParallelClusterComputePolicy"
  role   = aws_iam_role.parallelcluster_compute[0].id
  policy = data.aws_iam_policy_document.parallelcluster_compute[0].json
}

###############################################################################
# HyperPod Execution Role
###############################################################################

data "aws_iam_policy_document" "sagemaker_assume_role" {
  count = var.create_hyperpod_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "hyperpod_execution" {
  count = var.create_hyperpod_role ? 1 : 0

  statement {
    sid    = "S3Access"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "FSxAccess"
    effect = "Allow"

    actions = [
      "fsx:Describe*",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "hyperpod_execution" {
  count = var.create_hyperpod_role ? 1 : 0

  name               = "HyperPodExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "hyperpod_execution_sagemaker" {
  count = var.create_hyperpod_role ? 1 : 0

  role       = aws_iam_role.hyperpod_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerClusterInstanceRolePolicy"
}

resource "aws_iam_role_policy" "hyperpod_execution" {
  count = var.create_hyperpod_role ? 1 : 0

  name   = "HyperPodExecutionPolicy"
  role   = aws_iam_role.hyperpod_execution[0].id
  policy = data.aws_iam_policy_document.hyperpod_execution[0].json
}

###############################################################################
# S3 Replication Role
###############################################################################

data "aws_iam_policy_document" "s3_assume_role" {
  count = var.create_s3_replication_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "s3_replication" {
  count = var.create_s3_replication_role ? 1 : 0

  statement {
    sid    = "SourceBucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [var.s3_source_bucket_arn]
  }

  statement {
    sid    = "SourceObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${var.s3_source_bucket_arn}/*"]
  }

  statement {
    sid    = "DestinationObjectAccess"
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = [for arn in var.s3_destination_bucket_arns : "${arn}/*"]
  }

  statement {
    sid    = "SourceKMSDecrypt"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
    ]

    resources = [aws_kms_key.shared.arn]
  }

  statement {
    sid    = "DestinationKMSEncrypt"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
    ]

    resources = var.kms_key_arns
  }
}

resource "aws_iam_role" "s3_replication" {
  count = var.create_s3_replication_role ? 1 : 0

  name               = "S3ReplicationRole"
  assume_role_policy = data.aws_iam_policy_document.s3_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy" "s3_replication" {
  count = var.create_s3_replication_role ? 1 : 0

  name   = "S3ReplicationPolicy"
  role   = aws_iam_role.s3_replication[0].id
  policy = data.aws_iam_policy_document.s3_replication[0].json
}
