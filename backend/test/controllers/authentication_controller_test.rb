require "test_helper"

class AuthenticationControllerTest < ActionDispatch::IntegrationTest
  # ─── POST /login ──────────────────────────────────────────────────────────

  test "login bem-sucedido retorna token e dados do usuario" do
    post "/login", params: { email: "alice@example.com", password: "password123" }, as: :json
    assert_response :ok
    json = JSON.parse(response.body)
    assert json.key?("token"), "Resposta deve conter 'token'"
    assert_equal "alice@example.com", json.dig("user", "email")
    assert_equal "Alice", json.dig("user", "name")
  end

  test "login com senha errada retorna 401" do
    post "/login", params: { email: "alice@example.com", password: "senha_errada" }, as: :json
    assert_response :unauthorized
    assert_includes JSON.parse(response.body)["error"], "Invalid"
  end

  test "login com email inexistente retorna 401" do
    post "/login", params: { email: "naoexiste@example.com", password: "qualquer" }, as: :json
    assert_response :unauthorized
  end

  # ─── VULN-08: mesma resposta e mesmo custo para conta existente/inexistente ─

  test "email inexistente e senha errada geram a mesma resposta" do
    post "/login", params: { email: "naoexiste@example.com", password: "senha_errada" }, as: :json
    body_unknown = response.body
    post "/login", params: { email: "alice@example.com", password: "senha_errada" }, as: :json
    assert_equal body_unknown, response.body
  end

  test "login ignora maiusculas e espacos no email" do
    post "/login", params: { email: "  Alice@Example.COM ", password: "password123" }, as: :json
    assert_response :ok
  end

  # ─── POST /signup ─────────────────────────────────────────────────────────

  test "registro bem-sucedido cria usuario e retorna token" do
    assert_difference "User.count", 1 do
      post "/signup", params: {
        name: "Novo Usuario",
        email: "novo@example.com",
        password: "senha123",
        password_confirmation: "senha123"
      }, as: :json
    end
    assert_response :created
    json = JSON.parse(response.body)
    assert json.key?("token")
    assert_equal "novo@example.com", json.dig("user", "email")
  end

  test "registro com email duplicado retorna 422" do
    post "/signup", params: {
      name: "Copia Alice",
      email: "alice@example.com",
      password: "senha123"
    }, as: :json
    assert_response :unprocessable_entity
    assert JSON.parse(response.body).key?("errors")
  end

  test "registro sem nome retorna 422" do
    post "/signup", params: { email: "sem@nome.com", password: "senha123" }, as: :json
    assert_response :unprocessable_entity
  end

  # ─── DELETE /logout ───────────────────────────────────────────────────────

  test "logout autenticado retorna 200" do
    delete "/logout", headers: auth_headers_for(users(:alice))
    assert_response :ok
  end

  test "logout sem token retorna 401" do
    delete "/logout"
    assert_response :unauthorized
  end

  # ─── VULN-02: token revogado no logout / validação estrita do JWT ────────

  test "token deixa de funcionar depois do logout" do
    headers = auth_headers_for(users(:alice))
    get "/me", headers: headers
    assert_response :ok

    delete "/logout", headers: headers
    assert_response :ok

    get "/me", headers: headers
    assert_response :unauthorized
  end

  test "logout de um token nao derruba outra sessao do mesmo usuario" do
    session_a = auth_headers_for(users(:alice))
    session_b = auth_headers_for(users(:alice))
    delete "/logout", headers: session_a
    get "/me", headers: session_b
    assert_response :ok
  end

  test "logout grava o jti do token na lista de revogados" do
    headers = auth_headers_for(users(:alice))
    assert_difference "RevokedToken.count", 1 do
      delete "/logout", headers: headers
    end
    delete "/logout", headers: headers # segundo logout: token já revogado
    assert_response :unauthorized
  end

  test "rejeita token com alg none" do
    claims = { user_id: users(:alice).id, exp: 1.hour.from_now.to_i, iat: Time.current.to_i, jti: SecureRandom.uuid }
    token = JWT.encode(claims, nil, "none")
    get "/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end

  test "rejeita token assinado com outra chave" do
    claims = { user_id: users(:alice).id, exp: 1.hour.from_now.to_i, iat: Time.current.to_i, jti: SecureRandom.uuid }
    token = JWT.encode(claims, "chave-do-atacante", "HS256")
    get "/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end

  test "rejeita token expirado" do
    token = JsonWebToken.encode({ user_id: users(:alice).id }, 1.minute.ago)
    get "/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end

  test "rejeita token sem jti" do
    claims = { user_id: users(:alice).id, exp: 1.hour.from_now.to_i, iat: Time.current.to_i }
    token = JWT.encode(claims, Rails.application.key_generator.generate_key("coursesphere/jwt-hs256", 64), "HS256")
    get "/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end
end
