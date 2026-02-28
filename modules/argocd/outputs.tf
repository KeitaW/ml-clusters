output "argocd_namespace" {
  description = "The namespace where ArgoCD is deployed"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "argocd_release_name" {
  description = "The name of the ArgoCD Helm release"
  value       = helm_release.argocd.name
}
