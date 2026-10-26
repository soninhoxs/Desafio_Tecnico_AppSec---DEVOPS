class AuthenticationController < ApplicationController
  skip_before_action :authorize_request, only: :login

  # Camada 1: limite por IP (store compartilhado entre réplicas).
  rate_limit(**RateLimiting::LOGIN_LIMIT, only: :login, name: "login-by-ip",
    store: RateLimiting.store, with: -> { render_rate_limited })

  def login
    email = params[:email].to_s
    # authenticate_by gasta o mesmo tempo (bcrypt) exista ou não o e-mail,
    # então o tempo de resposta não revela quais contas existem.
    user = User.authenticate_by(email: email, password: params[:password].to_s)
    account = user || User.find_by(email: email)

    # Camada 2: bloqueio temporário da conta após falhas seguidas.
    # Mesmo com a senha certa, conta bloqueada não entra — e a resposta é a
    # mesma de credencial inválida, para não revelar o bloqueio.
    if account&.locked?
      render_invalid_credentials
    elsif user
      user.register_successful_login!
      render json: { token: JsonWebToken.encode(user_id: user.id), user: user_json(user) }, status: :ok
    else
      account&.register_failed_login!
      render_invalid_credentials
    end
  end

  # Revoga o token usado nesta requisição: a partir daqui ele não autentica
  # mais, mesmo que ainda não tenha expirado.
  def logout
    RevokedToken.revoke!(current_token_claims)
    render json: { message: "Logged out successfully" }, status: :ok
  end

  private

  def render_invalid_credentials
    render json: { error: "Invalid email or password" }, status: :unauthorized
  end

  def user_json(user)
    { id: user.id, email: user.email, name: user.name }
  end
end
