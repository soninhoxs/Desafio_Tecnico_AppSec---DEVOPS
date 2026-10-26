require "json"
require "socket"
require "digest"
require "active_support/core_ext/object/blank"
require "prometheus/client"
require "prometheus/client/formats/text"

# Instrumentação da API: logs estruturados (JSON), métricas Prometheus e
# eventos de segurança. Carregado explicitamente em config/application.rb
# (fora do autoloader) porque o middleware e o formatter de log são
# referenciados durante o boot.
module Observability
  BOOTED_AT = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # Identifica a réplica que atendeu: nome do container (compose) ou do pod (k8s).
  def self.instance_id
    @instance_id ||= ENV["INSTANCE_ID"].presence || ENV["HOSTNAME"].presence || Socket.gethostname
  end

  def self.app_version
    ENV.fetch("APP_VERSION", "dev")
  end

  def self.uptime_seconds
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - BOOTED_AT).round
  end

  # Header X-Served-By (usado para demonstrar o balanceamento). Desligado por
  # padrão: nome de host interno é informação que não precisa vazar.
  def self.expose_instance_header?
    ENV["EXPOSE_INSTANCE_HEADER"] == "true"
  end
end

require_relative "json_log_formatter"
require_relative "metrics"
require_relative "security_events"
require_relative "request_telemetry"
