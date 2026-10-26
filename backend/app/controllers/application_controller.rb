class ApplicationController < ActionController::API
  before_action :authorize_request

  private

  attr_reader :current_user

  def authorize_request
    header = request.headers["Authorization"]
    token = header.split(" ").last if header
    decoded = JsonWebToken.decode(token)

    if decoded
      @current_user = User.find_by(id: decoded[:user_id])
    end

    unless @current_user
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  # Resposta única para "autenticado, mas sem permissão sobre o recurso".
  def deny_access!(_resource = nil)
    render json: { error: "Ação não permitida para este utilizador" }, status: :forbidden
  end
end
