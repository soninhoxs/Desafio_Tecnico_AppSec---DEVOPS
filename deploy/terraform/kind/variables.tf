variable "repo_url" {
  description = "URL HTTPS do repositório Git observado pelo ArgoCD (ex.: https://github.com/<usuario>/coursesphere.git)."
  type        = string

  validation {
    condition     = can(regex("^https://", var.repo_url))
    error_message = "Use a URL HTTPS do repositório."
  }
}

variable "target_revision" {
  description = "Branch/tag que o ArgoCD sincroniza."
  type        = string
  default     = "main"
}

variable "app_overlay" {
  description = "Overlay da aplicação: kind (imagens do GHCR) ou kind-local (imagens carregadas com scripts/kind_load_images.sh)."
  type        = string
  default     = "kind"

  validation {
    condition     = contains(["kind", "kind-local"], var.app_overlay)
    error_message = "Valores aceitos: kind, kind-local."
  }
}

variable "cluster_name" {
  description = "Nome do cluster kind."
  type        = string
  default     = "coursesphere"
}

variable "worker_count" {
  description = "Quantidade de nós worker (as réplicas da API se espalham entre eles)."
  type        = number
  default     = 2
}

variable "http_port" {
  description = "Porta do host que recebe o tráfego HTTP do ingress (Traefik)."
  type        = number
  default     = 8080
}

variable "argocd_chart_version" {
  description = "Versão do chart argo-cd (fixa)."
  type        = string
  default     = "10.11.6"
}

variable "argocd_apps_chart_version" {
  description = "Versão do chart argocd-apps (fixa)."
  type        = string
  default     = "2.0.7"
}
