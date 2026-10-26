# CORS: só as origens listadas em CORS_ORIGINS (separadas por vírgula).
#
# No ambiente com balanceador (docker compose / Kubernetes) o frontend e a
# API são servidos pela MESMA origem (/ e /api), então CORS nem é usado.
# A lista só importa quando o frontend roda separado (ex.: Vite em :5173).
origins = ENV.fetch("CORS_ORIGINS", "http://localhost:5173").split(",").map(&:strip).reject(&:empty?)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*origins)

    resource "*",
      headers: %w[Authorization Content-Type Accept],
      methods: %i[get post put patch delete options head],
      max_age: 600
  end
end
