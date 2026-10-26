require "test_helper"

class ObservabilityTest < ActionDispatch::IntegrationTest
  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  test "liveness responde sem autenticacao" do
    get "/health/live"
    assert_response :ok
    assert_equal "ok", JSON.parse(response.body)["status"]
  end

  test "readiness verifica o banco" do
    get "/health/ready"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert_equal "ok", body.dig("checks", "database", "status")
  end

  test "/health e alias da readiness" do
    get "/health"
    assert_response :ok
    assert JSON.parse(response.body).key?("checks")
  end

  test "metrics expoe contadores http no formato Prometheus" do
    get "/courses" # 401, mas conta como requisição
    get "/metrics"
    assert_response :ok
    assert_includes response.media_type, "text/plain"
    assert_match(/http_server_requests_total\{method="GET",route="\/courses",status="401"\}/, response.body)
    assert_match(/http_server_request_duration_seconds_bucket/, response.body)
  end

  test "metrics exige token quando METRICS_TOKEN esta definido" do
    with_env("METRICS_TOKEN" => "segredo-de-teste") do
      get "/metrics"
      assert_response :unauthorized
      get "/metrics", headers: { "Authorization" => "Bearer errado" }
      assert_response :unauthorized
      get "/metrics", headers: { "Authorization" => "Bearer segredo-de-teste" }
      assert_response :ok
    end
  end

  test "falha de login vira evento de seguranca nas metricas" do
    post "/login", params: { email: "alice@example.com", password: "errada" }, as: :json
    get "/metrics"
    assert_match(/coursesphere_security_events_total\{event="login_failure"\} [1-9]/, response.body)
  end

  test "header X-Served-By so aparece quando habilitado" do
    get "/health/live"
    assert_nil response.headers["x-served-by"]
    with_env("EXPOSE_INSTANCE_HEADER" => "true", "INSTANCE_ID" => nil) do
      get "/health/live"
      assert response.headers["x-served-by"].present?
    end
  end

  test "respostas da API tem cabecalhos de seguranca e nao sao cacheadas" do
    get "/courses", headers: auth_headers_for(users(:alice))
    assert_response :ok
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "parametro obrigatorio ausente responde 400 em JSON" do
    post "/courses", params: { nada: 1 }, headers: auth_headers_for(users(:alice)), as: :json
    assert_response :bad_request
    assert JSON.parse(response.body).key?("error")
  end
end
