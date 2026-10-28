require "test_helper"

# Dependência externa (randomuser.me) com timeout, retry, circuit breaker,
# cache e fallback. O transporte HTTP é falso: nenhum teste sai para a rede.
class GuestInstructorClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  # Devolve (ou levanta) cada passo na ordem; o último se repete.
  class FakeTransport
    attr_reader :calls, :uris

    def initialize(*steps)
      @steps = steps
      @calls = 0
      @uris = []
    end

    def call(uri, open_timeout:, read_timeout:)
      @calls += 1
      @uris << uri
      step = @steps.length > 1 ? @steps.shift : @steps.first
      raise step if step.is_a?(Exception)

      step
    end
  end

  VALID_BODY = {
    results: [ {
      name: { first: "Ana", last: "Souza" },
      email: "ana@example.com",
      picture: { large: "https://randomuser.me/api/portraits/women/1.jpg" }
    } ]
  }.to_json

  def build_client(transport, breaker: nil)
    GuestInstructorClient.new(
      transport: transport, breaker: breaker,
      cache: ActiveSupport::Cache::MemoryStore.new,
      sleeper: ->(_seconds) { }, random: -> { 0.5 }
    )
  end

  test "devolve so nome, e-mail e foto" do
    result = build_client(FakeTransport.new(Response.new("200", VALID_BODY))).fetch(1)

    assert result.available?
    assert_equal :network, result.source
    assert_equal(
      { "name" => "Ana Souza", "email" => "ana@example.com",
        "picture_url" => "https://randomuser.me/api/portraits/women/1.jpg" },
      result.instructor
    )
  end

  test "descarta foto de outro dominio" do
    body = JSON.parse(VALID_BODY)
    body["results"][0]["picture"]["large"] = "https://atacante.example/x.jpg"

    result = build_client(FakeTransport.new(Response.new("200", body.to_json))).fetch(1)
    assert_nil result.instructor["picture_url"]
  end

  test "tenta de novo em erro transitorio e funciona na segunda tentativa" do
    transport = FakeTransport.new(Net::ReadTimeout.new, Response.new("200", VALID_BODY))

    assert build_client(transport).fetch(1).available?
    assert_equal 2, transport.calls
  end

  test "desiste depois do maximo de tentativas e devolve indisponivel (fallback)" do
    transport = FakeTransport.new(Response.new("503", ""))
    result = build_client(transport).fetch(1)

    assert_not result.available?
    assert_equal :error, result.source
    assert_equal GuestInstructorClient::MAX_ATTEMPTS, transport.calls
  end

  test "erro permanente (4xx) nao tem retry" do
    transport = FakeTransport.new(Response.new("404", ""))
    assert_not build_client(transport).fetch(1).available?
    assert_equal 1, transport.calls
  end

  test "resposta invalida vira indisponivel" do
    transport = FakeTransport.new(Response.new("200", "<html>erro</html>"))
    assert_not build_client(transport).fetch(1).available?
  end

  test "com o disjuntor aberto nao chama a rede" do
    breaker = CircuitBreaker.new(name: "randomuser", failure_threshold: 2, cooldown: 60)
    transport = FakeTransport.new(Response.new("500", ""))
    client = build_client(transport, breaker: breaker)

    2.times { client.fetch(1) }
    assert_equal :open, breaker.state

    calls_before = transport.calls
    result = client.fetch(2)
    assert_equal :circuit_open, result.source
    assert_equal calls_before, transport.calls
  end

  test "segunda leitura do mesmo curso vem do cache" do
    transport = FakeTransport.new(Response.new("200", VALID_BODY))
    client = build_client(transport)

    client.fetch(7)
    assert_equal :cache, client.fetch(7).source
    assert_equal 1, transport.calls
  end

  test "url fixa: so o id numerico do curso entra na consulta" do
    transport = FakeTransport.new(Response.new("200", VALID_BODY))
    client = build_client(transport)
    client.fetch(5)

    uri = transport.uris.last
    assert_equal "https", uri.scheme
    assert_equal "randomuser.me", uri.host
    assert_includes uri.query, "seed=course_5"

    assert_not client.fetch("5;http://169.254.169.254/").available?
    assert_equal 1, transport.calls, "entrada não numérica não pode virar requisição"
  end
end
