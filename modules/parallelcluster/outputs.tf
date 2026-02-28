output "pcluster_api_stack_name" {
  description = "The PCluster API stack name"
  value       = local.api_stack_name
}

output "clusters" {
  description = "Map of managed ParallelCluster clusters"
  value       = module.pcluster.clusters
}
