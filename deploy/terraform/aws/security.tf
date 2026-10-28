# Security groups. As descrições ficam sem acento (a AWS só aceita ASCII nelas).

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB: HTTPS da aplicacao e do Grafana, somente do CIDR autorizado"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS da aplicacao"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_grafana" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS do Grafana"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 3001
  to_port           = 3001
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Encaminha para o balanceador Nginx da instancia"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "alb_to_grafana" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Encaminha para o Grafana da instancia"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3001
  to_port                      = 3001
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Instancia da aplicacao: so recebe trafego do ALB, sem SSH"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Nginx (balanceador das 2 replicas) a partir do ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_ingress_rule" "grafana_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Grafana a partir do ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 3001
  to_port                      = 3001
}

# Saída só em 443 e 80, via NAT: imagens Docker, pacotes do Ubuntu (o espelho
# da AWS usa HTTP, com pacotes assinados), GitHub, Secrets Manager, SSM e a
# dependência externa randomuser.me. DNS e horário (endereços link-local da
# AWS) não passam pelo security group.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS de saida via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP de saida via NAT (espelho apt da AWS, pacotes assinados)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}
