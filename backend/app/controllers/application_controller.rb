class ApplicationController < ActionController::API
  before_action :authorize_request
  # Respostas da API com dados de usuário nunca devem ficar em cache.
  before_action :no_store

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  attr_reader :current_user, :current_token_claims

  def security_event(event, **fields)
    Observability::SecurityEvents.emit(event, request: request, **fields)
  end

  # Aceita somente "Authorization: Bearer <jwt>" válido e não revogado.
  def authorize_request
    token = bearer_token
    claims = JsonWebToken.decode(token)
    reason = if token.blank? then "missing"
    elsif claims.nil? then "invalid"
    elsif RevokedToken.revoked?(claims[:jti]) then "revoked"
    end

    @current_user = User.find_by(id: claims[:user_id]) if reason.nil?

    if @current_user
      @current_token_claims = claims
      request.env["coursesphere.user_id"] = @current_user.id
    else
      # Ausência de token é o caso comum (front sem sessão); só loga token ruim.
      security_event(:token_rejected, reason: reason || "unknown_user") unless reason == "missing"
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def bearer_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    token if scheme&.casecmp?("Bearer")
  end

  def render_rate_limited
    security_event(:rate_limited, action: "#{controller_name}##{action_name}")
    response.set_header("Retry-After", "60")
    render json: { error: "Too many requests. Try again later." }, status: :too_many_requests
  end

  # Resposta única para "autenticado, mas sem permissão sobre o recurso".
  def deny_access!(resource = nil)
    security_event(:access_denied, user_id: current_user&.id,
      resource: resource && "#{resource.class.name}##{resource.id}", action: "#{controller_name}##{action_name}")
    render json: { error: "Ação não permitida para este utilizador" }, status: :forbidden
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def render_bad_request(exception)
    render json: { error: "Bad request", detail: exception.message }, status: :bad_request
  end
end
