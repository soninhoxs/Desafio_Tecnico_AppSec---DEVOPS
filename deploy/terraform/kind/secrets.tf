# Segredos gerados aleatoriamente e gravados direto no cluster.
# Nunca passam pelo Git. ATENÇÃO: ficam no terraform.tfstate — em ambiente
# real use backend remoto criptografado (S3+KMS, GCS...) ou um gerenciador de
# segredos (AWS Secrets Manager/Vault + External Secrets Operator).

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "app_db" {
  length  = 32
  special = false
}

resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

resource "random_password" "metrics_token" {
  length  = 40
  special = false
}

resource "random_password" "demo_user" {
  length  = 20
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "coursesphere-db"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    POSTGRES_PASSWORD = random_password.postgres.result
    APP_DB_PASSWORD   = random_password.app_db.result
  }
}

resource "kubernetes_secret_v1" "api" {
  metadata {
    name      = "coursesphere-api"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    SECRET_KEY_BASE    = random_password.secret_key_base.result
    DATABASE_URL       = "postgres://coursesphere:${random_password.app_db.result}@coursesphere-db:5432/coursesphere_production"
    METRICS_TOKEN      = random_password.metrics_token.result
    DEMO_USER_PASSWORD = "Demo-${random_password.demo_user.result}"
  }
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}
