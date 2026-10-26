require_relative "boot"

# Só os railties que a API usa. Antes era "rails/all", que também carregava
# Active Storage (rotas públicas de upload em /rails/active_storage, alvo do
# CVE-2026-66066), Action Mailbox, Action Text, Action Cable e Action Mailer.
# O railtie do Active Job continua de fora: não há fila nem worker.
# A biblioteca entra só porque o Solid Cache traz ExpiryJob < ActiveJob::Base.
# A limpeza do cache usa thread (padrão da gem); o job nunca é enfileirado.
# Sem essa constante, o eager load do CI quebra ao carregar a classe.
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"
require "active_job"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Logs JSON, métricas e eventos de segurança (lib/observability, fora do autoloader).
require_relative "../lib/observability/boot"

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks observability])

    # Only loads a smaller set of middleware suitable for API only apps.
    config.api_only = true

    # Log + métricas por requisição (depois do RemoteIp: IP real atrás do LB).
    config.middleware.insert_after ActionDispatch::RemoteIp, Observability::RequestTelemetry

    # Cabeçalhos de segurança em todas as respostas da API.
    # (O frontend recebe CSP/HSTS próprios do Nginx.)
    config.action_dispatch.default_headers = {
      "X-Frame-Options" => "DENY",
      "X-Content-Type-Options" => "nosniff",
      "X-Permitted-Cross-Domain-Policies" => "none",
      "Referrer-Policy" => "no-referrer",
      "Cross-Origin-Resource-Policy" => "same-origin",
      "Content-Security-Policy" => "default-src 'none'; frame-ancestors 'none'"
    }
  end
end
