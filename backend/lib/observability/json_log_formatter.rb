require "logger"
require "time"

module Observability
  # Uma linha JSON por evento de log (pronto para Loki/ELK/CloudWatch).
  # Mensagens Hash viram campos; texto vira o campo "msg".
  class JsonLogFormatter < ::Logger::Formatter
    def call(severity, time, _progname, message)
      payload = {
        ts: time.utc.iso8601(3),
        level: severity,
        service: "coursesphere-api",
        instance: Observability.instance_id
      }

      case message
      when Hash
        payload.merge!(message)
      when Exception
        payload.merge!(event: "exception", error_class: message.class.name, error_message: message.message)
      else
        payload[:msg] = message.to_s.strip
      end

      "#{JSON.generate(payload)}\n"
    rescue StandardError => e
      # Nunca perder uma linha de log por erro de serialização.
      "#{JSON.generate(ts: Time.now.utc.iso8601(3), level: severity, msg: message.to_s, formatter_error: e.class.name)}\n"
    end
  end
end
