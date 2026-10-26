require_relative "boot"

# Só os componentes do Rails que a API usa. Antes era "rails/all", que também
# carregava Active Storage (com rotas públicas de upload em /rails/active_storage
# e alvo do CVE-2026-66066), Action Mailbox, Action Text, Action Cable,
# Action Mailer e Active Job — nenhum usado. Menos código carregado = menor
# superfície de ataque.
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

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
