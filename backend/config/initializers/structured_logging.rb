# Em produção cada requisição gera UMA linha JSON (Observability::RequestTelemetry).
# Desliga as linhas de texto "Processing by ..." / "Completed 200 OK ..." do
# Action Controller, que duplicariam a informação fora do formato JSON.
#
# A API não carrega o railtie completo do Action Pack, então a constante só
# existe quando esse subscriber foi de fato anexado. Chamar detach_from sem
# ela derruba o boot em produção (o job de migrate do compose morre aqui) e
# o E2E nunca chega no /health.
if Rails.env.production? && defined?(ActionController::LogSubscriber)
  ActionController::LogSubscriber.detach_from :action_controller
end
