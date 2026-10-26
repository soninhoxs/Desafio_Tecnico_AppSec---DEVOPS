class AuthenticationController < ApplicationController
  skip_before_action :authorize_request, only: :login

  def login
    # authenticate_by gasta o mesmo tempo (bcrypt) exista ou não o e-mail,
    # então o tempo de resposta não revela quais contas existem.
    user = User.authenticate_by(email: params[:email].to_s, password: params[:password].to_s)

    if user
      render json: { token: JsonWebToken.encode(user_id: user.id), user: user_json(user) }, status: :ok
    else
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
