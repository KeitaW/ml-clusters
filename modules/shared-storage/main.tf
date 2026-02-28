################################################################################
# Data Sources
################################################################################

data "aws_vpc" "selected" {
  id = var.vpc_id
}

################################################################################
# Locals
################################################################################

locals {
  s3_bucket_name = element(split(":::", var.s3_data_bucket_arn), 1)
}

################################################################################
# FSx for Lustre
################################################################################

resource "aws_fsx_lustre_file_system" "main" {
  storage_capacity            = var.fsx_storage_capacity
  subnet_ids                  = [var.private_subnet_ids[0]]
  deployment_type             = "PERSISTENT_2"
  per_unit_storage_throughput = var.fsx_throughput_per_unit
  data_compression_type       = "LZ4"
  kms_key_id                  = var.kms_key_arn
  security_group_ids          = [aws_security_group.fsx.id]

  tags = merge(var.tags, {
    Name = "ml-fsx-${var.account_name}-${var.aws_region}"
  })
}

resource "aws_security_group" "fsx" {
  name        = "ml-fsx-${var.account_name}-${var.aws_region}"
  description = "Security group for FSx Lustre filesystem"
  vpc_id      = var.vpc_id

  ingress {
    description = "Lustre traffic"
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "Lustre traffic"
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "ml-fsx-${var.account_name}-${var.aws_region}"
  })
}

resource "aws_fsx_data_repository_association" "main" {
  file_system_id       = aws_fsx_lustre_file_system.main.id
  data_repository_path = "s3://${local.s3_bucket_name}"
  file_system_path     = "/data"

  s3 {
    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }

    auto_export_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
}

################################################################################
# EFS
################################################################################

resource "aws_efs_file_system" "main" {
  encrypted        = true
  kms_key_id       = var.kms_key_arn
  throughput_mode  = "elastic"
  performance_mode = "generalPurpose"

  tags = merge(var.tags, {
    Name = "ml-efs-${var.account_name}-${var.aws_region}"
  })
}

resource "aws_efs_mount_target" "main" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "ml-efs-${var.account_name}-${var.aws_region}"
  description = "Security group for EFS filesystem"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS traffic"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "ml-efs-${var.account_name}-${var.aws_region}"
  })
}

resource "aws_efs_access_point" "home" {
  file_system_id = aws_efs_file_system.main.id

  root_directory {
    path = "/home"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(var.tags, {
    Name = "ml-efs-home-${var.account_name}-${var.aws_region}"
  })
}
