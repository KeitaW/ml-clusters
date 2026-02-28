mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

variables {
  account_name       = "test"
  aws_region         = "us-east-1"
  vpc_id             = "vpc-test12345"
  private_subnet_ids = ["subnet-a", "subnet-b"]
  kms_key_arn        = "arn:aws:kms:us-east-1:123456789012:key/test-key"
  s3_data_bucket_arn = "arn:aws:s3:::test-data-bucket"
}

run "fsx_lustre_configuration" {
  command = plan

  assert {
    condition     = aws_fsx_lustre_file_system.main.deployment_type == "PERSISTENT_2"
    error_message = "FSx should use PERSISTENT_2 for production ML workloads"
  }

  assert {
    condition     = aws_fsx_lustre_file_system.main.data_compression_type == "LZ4"
    error_message = "FSx should use LZ4 compression for throughput"
  }

  assert {
    condition     = aws_fsx_lustre_file_system.main.per_unit_storage_throughput == 500
    error_message = "FSx should default to 500 MB/s/TiB throughput"
  }

  assert {
    condition     = aws_fsx_lustre_file_system.main.storage_capacity == 4800
    error_message = "FSx should default to 4800 GiB storage capacity"
  }

  assert {
    condition     = aws_fsx_lustre_file_system.main.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/test-key"
    error_message = "FSx should be encrypted with the provided KMS key"
  }
}

run "fsx_security_group" {
  command = plan

  assert {
    condition     = aws_security_group.fsx.name == "ml-fsx-test-us-east-1"
    error_message = "FSx security group name should follow naming convention"
  }
}

run "fsx_data_repository_association" {
  command = plan

  assert {
    condition     = aws_fsx_data_repository_association.main.data_repository_path == "s3://test-data-bucket"
    error_message = "DRA should link to the correct S3 bucket"
  }

  assert {
    condition     = aws_fsx_data_repository_association.main.file_system_path == "/data"
    error_message = "DRA should mount at /data on the filesystem"
  }
}

run "efs_configuration" {
  command = plan

  assert {
    condition     = aws_efs_file_system.main.encrypted == true
    error_message = "EFS must be encrypted at rest"
  }

  assert {
    condition     = aws_efs_file_system.main.throughput_mode == "elastic"
    error_message = "EFS should use elastic throughput for variable ML workloads"
  }

  assert {
    condition     = aws_efs_file_system.main.performance_mode == "generalPurpose"
    error_message = "EFS should use generalPurpose performance mode"
  }
}

run "efs_mount_targets_per_subnet" {
  command = plan

  assert {
    condition     = length(aws_efs_mount_target.main) == 2
    error_message = "Should create one EFS mount target per private subnet"
  }
}

run "efs_access_point_home" {
  command = plan

  assert {
    condition     = aws_efs_access_point.home.root_directory[0].path == "/home"
    error_message = "EFS access point should serve /home directory"
  }

  assert {
    condition     = aws_efs_access_point.home.root_directory[0].creation_info[0].owner_uid == 1000
    error_message = "Home directory owner UID should be 1000"
  }

  assert {
    condition     = aws_efs_access_point.home.root_directory[0].creation_info[0].owner_gid == 1000
    error_message = "Home directory owner GID should be 1000"
  }

  assert {
    condition     = aws_efs_access_point.home.root_directory[0].creation_info[0].permissions == "755"
    error_message = "Home directory permissions should be 755"
  }
}

run "efs_security_group" {
  command = plan

  assert {
    condition     = aws_security_group.efs.name == "ml-efs-test-us-east-1"
    error_message = "EFS security group name should follow naming convention"
  }
}
