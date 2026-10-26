# Em produção cada requisição gera UMA linha JSON (Observability::RequestTelemetry).
# Desliga as linhas de texto "Processing by ..." / "Completed 200 OK ..." do
# Action Controller, que duplicariam a informação fora do formato JSON.
if Rails.env.production?
  ActionController::LogSubscriber.detach_from :action_controller
end
