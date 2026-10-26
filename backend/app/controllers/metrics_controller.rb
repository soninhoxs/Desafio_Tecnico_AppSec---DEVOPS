# GET /metrics — formato de texto do Prometheus.
#
# Não é para ser público: o balanceador/ingress não roteia /api/metrics, e se
# METRICS_TOKEN estiver definido o scrape precisa de "Authorization: Bearer <token>".
class MetricsController < ActionController::API
  def show
    return head :unauthorized unless authorized?

    render plain: Observability::Metrics.render, content_type: Prometheus::Client::Formats::Text::CONTENT_TYPE
  end

  private

  def authorized?
    expected = ENV["METRICS_TOKEN"].to_s
    return true if expected.empty?

    scheme, provided = request.authorization.to_s.split(" ", 2)
    scheme&.casecmp?("Bearer") && ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected)
  end
end
