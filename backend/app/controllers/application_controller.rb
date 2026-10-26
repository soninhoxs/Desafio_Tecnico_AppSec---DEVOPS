class ApplicationController < ActionController::API
  before_action :authorize_request

  private

  attr_reader :current_user, :current_token_claims

  # Aceita somente "Authorization: Bearer <jwt>" válido e não revogado.
  def authorize_request
    claims = JsonWebToken.decode(bearer_token)
    claims = nil if claims && RevokedToken.revoked?(claims[:jti])
    @current_user = User.find_by(id: claims[:user_id]) if claims

    if @current_user
      @current_token_claims = claims
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def bearer_token
    scheme, token = request.authorization.to_s.split(" ", 2)
    token if scheme&.casecmp?("Bearer")
  end

  def render_rate_limited
    response.set_header("Retry-After", "60")
    render json: { error: "Too many requests. Try again later." }, status: :too_many_requests
  end

  # Resposta única para "autenticado, mas sem permissão sobre o recurso".
  def deny_access!(_resource = nil)
    render json: { error: "Ação não permitida para este utilizador" }, status: :forbidden
  end
end
