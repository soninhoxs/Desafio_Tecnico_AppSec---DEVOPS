# Cluster Kubernetes local (kind) + bootstrap do GitOps.
#
#   terraform init
#   terraform apply -var repo_url=https://github.com/<usuario>/coursesphere.git
#
# O Terraform cria só a infraestrutura de base e os segredos. Tudo o que
# roda no cluster (plataforma e aplicação) é declarado no Git e aplicado
# pelo ArgoCD.

# ---------------------------------------------------------------- cluster
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # NodePort do Traefik -> localhost:<http_port>. Só em 127.0.0.1.
      extra_port_mappings {
        container_port = 30080
        host_port      = var.http_port
        listen_address = "127.0.0.1"
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

# ---------------------------------------------------------------- namespaces
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "coursesphere"
    labels = {
      # Pod Security Admission: bloqueia pods privilegiados, root, hostPath etc.
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/audit"           = "restricted"
    }
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      # node-exporter precisa de hostNetwork/hostPID (privilegiado por natureza).
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}
