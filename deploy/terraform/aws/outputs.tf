output "app_url" {
  description = "Aplicação (HTTPS no ALB; certificado autoassinado)."
  value       = "https://${aws_lb.this.dns_name}"
}

output "grafana_url" {
  description = "Grafana (HTTPS no ALB, porta 3001). Usuário admin; senha no Secrets Manager."
  value       = "https://${aws_lb.this.dns_name}:3001"
}

output "instance_id" {
  description = "Instância da aplicação (sem IP público)."
  value       = aws_instance.app.id
}

output "secret_arn" {
  description = "Segredo com as variáveis do .env."
  value       = aws_secretsmanager_secret.app.arn
}

output "alb_certificate_pem" {
  description = "Certificado público do ALB (para clientes confiarem nele: SSL_CERT_FILE)."
  value       = tls_self_signed_cert.alb.cert_pem
}

output "ssm_session_command" {
  description = "Acesso administrativo à instância, sem SSH."
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.region}"
}

output "bootstrap_log_command" {
  description = "Acompanha o bootstrap da instância pelo console serial."
  value       = "aws ec2 get-console-output --latest --instance-id ${aws_instance.app.id} --region ${var.region} --query Output --output text"
}
