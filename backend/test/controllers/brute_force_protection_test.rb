require "test_helper"

# VULN-03: proteção contra força bruta / credential stuffing.
class BruteForceProtectionTest < ActionDispatch::IntegrationTest
  def login(email, password, ip: "203.0.113.10")
    post "/login", params: { email: email, password: password }, as: :json,
      env: { "REMOTE_ADDR" => ip }
  end

  test "bloqueia a conta apos 5 falhas seguidas, mesmo com a senha correta depois" do
    User::MAX_FAILED_LOGINS.times { |i| login("alice@example.com", "errada-#{i}", ip: "203.0.113.#{i + 1}") }
    assert users(:alice).reload.locked?

    login("alice@example.com", "password123", ip: "203.0.113.99")
    assert_response :unauthorized
    assert_equal "Invalid email or password", JSON.parse(response.body)["error"],
      "conta bloqueada deve responder igual a credencial inválida"
  end

  test "bloqueio e temporario" do
    User::MAX_FAILED_LOGINS.times { |i| login("alice@example.com", "errada-#{i}", ip: "203.0.113.#{i + 1}") }
    travel User::LOCKOUT_PERIOD + 1.second do
      login("alice@example.com", "password123", ip: "203.0.113.50")
      assert_response :ok
    end
  end

  test "login bem-sucedido zera o contador de falhas" do
    3.times { |i| login("alice@example.com", "errada-#{i}") }
    login("alice@example.com", "password123")
    assert_response :ok
    assert_equal 0, users(:alice).reload.failed_login_attempts
  end

  test "falhas de uma conta nao bloqueiam outra" do
    User::MAX_FAILED_LOGINS.times { |i| login("alice@example.com", "errada-#{i}", ip: "203.0.113.#{i + 1}") }
    login("bob@example.com", "password123", ip: "203.0.113.77")
    assert_response :ok
  end

  test "limita tentativas de login por IP (429)" do
    limit = RateLimiting::LOGIN_LIMIT[:to]
    limit.times { |i| login("naoexiste#{i}@example.com", "x") }
    assert_response :unauthorized

    login("naoexiste@example.com", "x")
    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]

    # Outro IP não é afetado.
    login("alice@example.com", "password123", ip: "198.51.100.1")
    assert_response :ok
  end

  test "limita cadastros por IP (429)" do
    limit = RateLimiting::SIGNUP_LIMIT[:to]
    limit.times { |i| post "/signup", params: { email: "invalido-#{i}" }, as: :json }
    post "/signup", params: { email: "mais-um" }, as: :json
    assert_response :too_many_requests
  end
end
