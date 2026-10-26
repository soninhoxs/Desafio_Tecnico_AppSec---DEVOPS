module Observability
  # Middleware Rack: uma linha de log JSON + métricas por requisição.
  #
  # Fica logo depois do ActionDispatch::RemoteIp (já sabe o IP real do
  # cliente, atrás do balanceador) e FORA do ShowExceptions: enxerga o status
  # final, inclusive os 500 gerados por exceção (lidos de
  # env["action_dispatch.exception"]).
  class RequestTelemetry
    QUIET_PATHS = %w[/health /health/live /health/ready /metrics].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Metrics::HTTP_IN_FLIGHT.increment
      status, headers, body = @app.call(env)
      headers["x-served-by"] = Observability.instance_id if Observability.expose_instance_header?
      [ status, headers, body ]
    rescue Exception => e # rubocop:disable Lint/RescueException -- registra e propaga
      error = e
      status = 500
      raise
    ensure
      Metrics::HTTP_IN_FLIGHT.decrement
      record(env, status || 500, started, error || env["action_dispatch.exception"])
    end

    private

    def record(env, status, started, error)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      request = ActionDispatch::Request.new(env)
      method = request.request_method
      route = route_label(env)

      Metrics::HTTP_REQUESTS.increment(labels: { method: method, route: route, status: status.to_s })
      Metrics::HTTP_DURATION.observe(duration, labels: { method: method, route: route })

      return if QUIET_PATHS.include?(request.path) && status < 500

      payload = {
        event: "http_request",
        method: method,
        path: request.path, # sem query string: evita logar tokens/PII
        route: route,
        status: status,
        duration_ms: (duration * 1000).round(2),
        request_id: env["action_dispatch.request_id"],
        user_id: env["coursesphere.user_id"],
        remote_ip: request.remote_ip,
        user_agent: request.user_agent.to_s[0, 200]
      }
      if error
        payload[:error_class] = error.class.name
        payload[:error_message] = error.message.to_s[0, 500]
      end

      log(status, payload.compact)
    rescue StandardError => e
      # Telemetria nunca deve derrubar a requisição.
      Rails.logger&.error({ event: "telemetry_error", error_class: e.class.name, error_message: e.message })
    end

    # Rótulo de baixa cardinalidade: o padrão da rota ("/courses/:id"),
    # nunca o caminho com IDs reais.
    def route_label(env)
      pattern = env["action_dispatch.route_uri_pattern"]
      pattern ? pattern.delete_suffix("(.:format)") : "unmatched"
    end

    def log(status, payload)
      if status >= 500
        Rails.logger.error(payload)
      elsif status >= 400
        Rails.logger.warn(payload)
      else
        Rails.logger.info(payload)
      end
    end
  end
end
