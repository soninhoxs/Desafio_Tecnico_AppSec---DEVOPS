# Segredos e permissões da instância.
#
# Os segredos são gerados como valores efêmeros e gravados por um atributo
# write-only: chegam ao Secrets Manager, mas não ficam no state do Terraform.
# A instância lê o segredo no boot e monta o .env (modo 600).

ephemeral "random_password" "postgres" {
  length  = 32
  special = false
}

ephemeral "random_password" "app_db" {
  length  = 32
  special = false
}

ephemeral "random_password" "secret_key_base" {
  length  = 96
  special = false
}

ephemeral "random_password" "metrics_token" {
  length  = 40
  special = false
}

ephemeral "random_password" "grafana_admin" {
  length  = 24
  special = false
}

ephemeral "random_password" "demo_user" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name_prefix = "${var.name}/app-env-"
  description = "Variaveis secretas do .env da aplicacao, lidas pela instancia no boot."

  # Ambiente de demonstração: o destroy apaga o segredo na hora.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string_wo = jsonencode({
    POSTGRES_PASSWORD      = ephemeral.random_password.postgres.result
    APP_DB_PASSWORD        = ephemeral.random_password.app_db.result
    SECRET_KEY_BASE        = ephemeral.random_password.secret_key_base.result
    METRICS_TOKEN          = ephemeral.random_password.metrics_token.result
    GRAFANA_ADMIN_PASSWORD = ephemeral.random_password.grafana_admin.result
    ALLOW_DEMO_SEED        = "true"
    DEMO_USER_PASSWORD     = "Demo-${ephemeral.random_password.demo_user.result}"
  })
  secret_string_wo_version = var.secret_version
}

# Papel da instância: SSM (acesso administrativo sem SSH) e leitura de UM segredo.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_app_secret" {
  statement {
    sid       = "ReadOnlyTheAppSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app.arn]
  }
}

resource "aws_iam_role_policy" "read_app_secret" {
  name   = "read-app-secret"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.read_app_secret.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app-instance"
  role = aws_iam_role.app.name
}
