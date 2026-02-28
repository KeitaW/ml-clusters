output "fsx_filesystem_id" {
  description = "ID of the FSx for Lustre filesystem"
  value       = aws_fsx_lustre_file_system.main.id
}

output "fsx_filesystem_arn" {
  description = "ARN of the FSx for Lustre filesystem"
  value       = aws_fsx_lustre_file_system.main.arn
}

output "fsx_dns_name" {
  description = "DNS name of the FSx for Lustre filesystem"
  value       = aws_fsx_lustre_file_system.main.dns_name
}

output "fsx_mount_name" {
  description = "Mount name of the FSx for Lustre filesystem"
  value       = aws_fsx_lustre_file_system.main.mount_name
}

output "efs_filesystem_id" {
  description = "ID of the EFS filesystem"
  value       = aws_efs_file_system.main.id
}

output "efs_filesystem_arn" {
  description = "ARN of the EFS filesystem"
  value       = aws_efs_file_system.main.arn
}

output "efs_access_point_id" {
  description = "ID of the EFS access point for /home"
  value       = aws_efs_access_point.home.id
}
