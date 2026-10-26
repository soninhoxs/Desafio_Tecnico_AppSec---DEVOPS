output "kubeconfig_path" {
  description = "Arquivo kubeconfig do cluster (use com KUBECONFIG=...)."
  value       = kind_cluster.this.kubeconfig_path
}

output "urls" {
  description = "Endereços expostos pelo Traefik."
  value = {
    app     = "http://coursesphere.localhost:${var.http_port}"
    api     = "http://coursesphere.localhost:${var.http_port}/api/health"
    argocd  = "http://argocd.localhost:${var.http_port}"
    grafana = "http://grafana.localhost:${var.http_port}"
  }
}

output "grafana_admin_password" {
  description = "Senha do usuário admin do Grafana."
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "demo_user_password" {
  description = "Senha dos usuários de demonstração (tech@ e design@coursesphere.com)."
  value       = "Demo-${random_password.demo_user.result}"
  sensitive   = true
}

output "argocd_admin_password_command" {
  description = "Comando para ler a senha inicial do admin do ArgoCD."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
