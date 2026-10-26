class UsersController < ApplicationController
  skip_before_action :authorize_request, only: :create

  # Limita criação de contas em massa e enumeração de e-mails via cadastro.
  rate_limit(**RateLimiting::SIGNUP_LIMIT, only: :create, name: "signup-by-ip",
    store: RateLimiting.store, with: -> { render_rate_limited })

  def me
    render json: { 
      user: { 
        id: @current_user.id, 
        email: @current_user.email, 
        name: @current_user.name 
      } 
    }, status: :ok
  end

  def create
    user = User.new(user_params)
    if user.save
      security_event(:signup_success, user_id: user.id)
      token = JsonWebToken.encode(user_id: user.id)
      render json: { 
        token: token,
        user: { 
          id: user.id,
          email: user.email, 
          name: user.name 
        } 
      }, status: :created
    else
      security_event(:signup_failure, fields: user.errors.attribute_names.map(&:to_s))
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
  def user_params
    params.permit(:name, :email, :password, :password_confirmation)
  end
end