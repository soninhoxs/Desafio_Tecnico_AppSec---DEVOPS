# Instância da aplicação: Ubuntu 24.04 na sub-rede privada, sem IP público e
# sem chave SSH. Ela roda o mesmo docker compose do ambiente local (Nginx +
# 2 réplicas da API + PostgreSQL + Prometheus + Grafana).

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.ubuntu.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = false

  # IMDSv2 obrigatório; hop limit 1 impede que os containers alcancem o
  # serviço de metadados (e as credenciais do papel da instância).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region     = var.region
    repo_url   = var.repo_url
    git_ref    = var.git_ref
    secret_arn = aws_secretsmanager_secret.app.arn
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.name}-app" }

  # A instância só sobe depois que a saída para a internet e o segredo existem.
  depends_on = [
    aws_route_table_association.private,
    aws_nat_gateway.this,
    aws_secretsmanager_secret_version.app,
    aws_iam_role_policy.read_app_secret,
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}
