module Observability
  # Eventos de autenticação/autorização: viram log JSON + métrica
  # coursesphere_security_events_total{event=...}, base dos alertas de
  # força bruta e de picos de acesso negado.
  module SecurityEvents
    WARN_EVENTS = %w[login_failure login_blocked_locked account_locked rate_limited token_rejected access_denied].freeze

    def self.emit(event, request: nil, **fields)
      event = event.to_s
      Metrics::SECURITY_EVENTS.increment(labels: { event: event })

      payload = { event: "security.#{event}" }
      if request
        payload[:request_id] = request.request_id
        payload[:remote_ip] = request.remote_ip
        payload[:path] = request.path
      end
      payload.merge!(fields)

      logger = defined?(Rails) && Rails.logger
      return unless logger

      WARN_EVENTS.include?(event) ? logger.warn(payload.compact) : logger.info(payload.compact)
    rescue StandardError
      nil
    end

    # Nunca registra o e-mail em claro: um hash curto permite correlacionar
    # tentativas contra a mesma conta sem guardar PII nos logs.
    def self.fingerprint(value)
      Digest::SHA256.hexdigest(value.to_s.strip.downcase)[0, 16]
    end
  end
end
