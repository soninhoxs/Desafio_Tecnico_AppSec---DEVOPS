# ArgoCD + Application "root" (app-of-apps). A partir daqui o cluster é
# reconciliado continuamente com o que está no Git.

locals {
  # Sem isto o ArgoCD não avalia a saúde de Applications filhas, e as sync
  # waves do app-of-apps não esperariam a plataforma ficar pronta.
  application_health_lua = <<-EOT
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
  EOT
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  timeout    = 600
  wait       = true

  values = [yamlencode({
    dex = { enabled = false }
    configs = {
      params = {
        # TLS termina no Traefik; o argocd-server fala HTTP dentro do cluster.
        "server.insecure" = true
      }
      cm = {
        "resource.customizations.health.argoproj.io_Application" = local.application_health_lua
        "timeout.reconciliation"                                 = "60s"
      }
    }
    server = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hostname         = "argocd.localhost"
      }
    }
  })]
}

resource "helm_release" "root_app" {
  name       = "coursesphere-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode({
    applications = {
      root = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "deploy/argocd/root"
          helm = {
            valuesObject = {
              repoURL        = var.repo_url
              targetRevision = var.target_revision
              appOverlay     = var.app_overlay
            }
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  # Os Secrets precisam existir antes da aplicação subir.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.api,
    kubernetes_secret_v1.db,
    kubernetes_secret_v1.grafana_admin,
  ]
}
