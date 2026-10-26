ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Roda testes em paralelo
    parallelize(workers: :number_of_processors)

    # Carrega todos os fixtures
    fixtures :all

    # Cada teste começa com o contador de rate limiting zerado.
    setup { RateLimiting.store.clear }

    # Helper: gera um token JWT válido para um usuário e retorna os headers de auth
    def auth_headers_for(user)
      token = JsonWebToken.encode(user_id: user.id)
      { "Authorization" => "Bearer #{token}" }
    end
  end
end
