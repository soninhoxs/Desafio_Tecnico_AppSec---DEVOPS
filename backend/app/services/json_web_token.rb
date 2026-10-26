# Emissão e validação dos JWT de sessão.
#
# - Algoritmo fixo (HS256) na validação: tokens "alg: none" ou com outro
#   algoritmo são recusados.
# - Claims obrigatórias: exp, iat, jti e user_id.
# - jti (id único do token) permite revogar um token específico no logout
#   (ver RevokedToken).
# - Chave própria para JWT, derivada do secret_key_base (separação de chaves):
#   vazar um token não ajuda a forjar cookies/outros usos do secret_key_base.
class JsonWebToken
  ALGORITHM = "HS256".freeze
  REQUIRED_CLAIMS = %w[exp iat jti user_id].freeze

  class << self
    def ttl
      ENV.fetch("JWT_TTL_MINUTES", "60").to_i.minutes
    end

    def encode(payload, exp = ttl.from_now)
      claims = payload.to_h.stringify_keys.merge(
        "exp" => exp.to_i,
        "iat" => Time.current.to_i,
        "jti" => SecureRandom.uuid
      )
      JWT.encode(claims, signing_key, ALGORITHM)
    end

    # Retorna os claims (com acesso indiferente) ou nil se o token for
    # inválido, expirado, mal formado ou assinado com outro algoritmo/chave.
    def decode(token)
      return nil if token.blank?

      claims, _header = JWT.decode(
        token, signing_key, true,
        algorithm: ALGORITHM,
        required_claims: REQUIRED_CLAIMS,
        verify_iat: true
      )
      claims.with_indifferent_access
    rescue JWT::DecodeError
      nil
    end

    private

    def signing_key
      @signing_key ||= Rails.application.key_generator.generate_key("coursesphere/jwt-hs256", 64).tap do |key|
        raise ArgumentError, "JWT signing key is empty" if key.blank?
      end
    end
  end
end
