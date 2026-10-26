require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Nunca mostra stack trace / detalhes de exceção para o cliente.
  config.consider_all_requests_local = false

  # TLS termina no balanceador/ingress.
  # ASSUME_SSL=true: o proxy na frente fala HTTPS com o cliente.
  # FORCE_SSL=true: redireciona HTTP->HTTPS e envia HSTS (produção real com TLS).
  config.assume_ssl = ENV["ASSUME_SSL"] == "true"
  config.force_ssl = ENV["FORCE_SSL"] == "true"
  config.ssl_options = {
    hsts: { expires: 1.year, subdomains: true },
    redirect: { exclude: ->(request) { request.path.start_with?("/health") || request.path == "/metrics" } }
  }

  # Logs estruturados: uma linha JSON por evento, em STDOUT (12-factor).
  # O request_id vai como campo do JSON (Observability::RequestTelemetry),
  # então não usamos log_tags. O Rails::Rack::Logger ("Started GET ...") sai
  # do stack: a linha de acesso agora é o evento http_request em JSON.
  stdout_logger = ActiveSupport::Logger.new($stdout)
  stdout_logger.formatter = Observability::JsonLogFormatter.new
  config.logger = ActiveSupport::TaggedLogging.new(stdout_logger)
  config.middleware.delete Rails::Rack::Logger

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Solid Cache (PostgreSQL): compartilhado entre réplicas; usado pelo rate limiting.
  config.cache_store = :solid_cache_store

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Proteção contra DNS rebinding / Host header: lista em ALLOWED_HOSTS
  # (ex.: "coursesphere.example.com,localhost"). Health checks e /metrics
  # ficam de fora porque são chamados pelo IP do pod/container.
  allowed_hosts = ENV.fetch("ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  if allowed_hosts.any?
    config.hosts = allowed_hosts
    config.host_authorization = { exclude: ->(request) { request.path.start_with?("/health") || request.path == "/metrics" } }
  end
end
