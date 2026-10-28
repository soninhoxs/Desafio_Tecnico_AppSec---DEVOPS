variable "region" {
  description = "Região da AWS."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Perfil do AWS CLI usado pelo provider (null = cadeia padrão de credenciais)."
  type        = string
  default     = null
}

variable "name" {
  description = "Prefixo dos recursos."
  type        = string
  default     = "coursesphere"
}

variable "allowed_cidr" {
  description = "Único bloco que alcança o ALB (HTTPS da aplicação e do Grafana). Use o seu IP público com /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0)) && var.allowed_cidr != "0.0.0.0/0"
    error_message = "Informe um CIDR válido e restrito (ex.: 203.0.113.10/32). 0.0.0.0/0 não é aceito."
  }
}

variable "repo_url" {
  description = "Repositório público clonado pela instância."
  type        = string
  default     = "https://github.com/soninhoxs/Desafio_Tecnico_AppSec---DEVOPS.git"

  validation {
    condition     = can(regex("^https://", var.repo_url))
    error_message = "Use a URL HTTPS do repositório."
  }
}

variable "git_ref" {
  description = "Commit (SHA completo) ou branch que a instância publica. Fixar o SHA deixa o deploy reproduzível."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[0-9a-f]{40}$|^[A-Za-z0-9._/-]+$", var.git_ref)) && var.git_ref != "v0-original"
    error_message = "Informe um SHA completo ou uma branch. A tag v0-original (versão vulnerável) não pode ir para a nuvem."
  }
}

variable "instance_type" {
  description = <<-EOT
    Tipo da instância. Precisa de pelo menos 4 GB de RAM para o build das imagens e o compose
    completo. Contas no plano gratuito da AWS só criam tipos elegíveis ao Free Tier
    (aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true):
    m7i-flex.large (8 GB) e c7i-flex.large (4 GB) atendem; t3.medium é recusada.
  EOT
  type        = string
  default     = "m7i-flex.large"
}

variable "root_volume_gb" {
  description = "Tamanho do disco (imagens Docker + volumes do PostgreSQL, Prometheus e Grafana)."
  type        = number
  default     = 30
}

variable "vpc_cidr" {
  description = "Bloco da VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "secret_version" {
  description = "Aumente para gerar e gravar novos segredos da aplicação (rotação)."
  type        = number
  default     = 1
}
