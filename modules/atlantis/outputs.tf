output "atlantis_namespace" {
  description = "The namespace where Atlantis is deployed"
  value       = kubernetes_namespace_v1.atlantis.metadata[0].name
}

output "atlantis_release_name" {
  description = "The name of the Atlantis Helm release"
  value       = helm_release.atlantis.name
}
