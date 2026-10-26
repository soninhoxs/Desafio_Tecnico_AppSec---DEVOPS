# Health checks (sem autenticação, sem rate limit).
#
# GET /health/live  -> liveness: o processo está de pé? (não toca no banco,
#                      para o orquestrador não reiniciar a API quando o
#                      problema é o banco)
# GET /health/ready -> readiness: consegue atender? (testa o PostgreSQL).
#                      503 tira a réplica do balanceador até se recuperar.
# GET /health       -> alias de /health/ready
class HealthController < ActionController::API
  def live
    render json: { status: "ok", instance: Observability.instance_id }
  end

  def ready
    checks = { database: database_check }
    healthy = checks.values.all? { |check| check[:status] == "ok" }

    render json: {
      status: healthy ? "ok" : "fail",
      instance: Observability.instance_id,
      version: Observability.app_version,
      uptime_seconds: Observability.uptime_seconds,
      checks: checks
    }, status: healthy ? :ok : :service_unavailable
  end

  private

  def database_check
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveRecord::Base.connection_pool.with_connection { |conn| conn.select_value("SELECT 1") }
    { status: "ok", latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2) }
  rescue StandardError => e
    { status: "fail", error: e.class.name }
  end
end
