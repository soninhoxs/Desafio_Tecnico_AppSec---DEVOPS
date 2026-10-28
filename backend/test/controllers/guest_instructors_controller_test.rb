require "test_helper"

class GuestInstructorsControllerTest < ActionDispatch::IntegrationTest
  Response = Struct.new(:code, :body)

  BODY = {
    results: [ {
      name: { first: "Ana", last: "Souza" },
      email: "ana@example.com",
      picture: { large: "https://randomuser.me/api/portraits/women/1.jpg" }
    } ]
  }.to_json

  def use_transport(transport)
    GuestInstructorClient.instance = GuestInstructorClient.new(
      transport: transport, cache: ActiveSupport::Cache::MemoryStore.new, sleeper: ->(_seconds) { }
    )
  end

  teardown { GuestInstructorClient.instance = nil }

  test "devolve o instrutor convidado do curso" do
    use_transport(->(_uri, **) { Response.new("200", BODY) })
    get "/courses/#{courses(:rails_course).id}/guest_instructor", headers: auth_headers_for(users(:alice))

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["available"]
    assert_equal "Ana Souza", json.dig("instructor", "name")
  end

  test "dependencia fora do ar responde 200 com available false (fallback, nao 5xx)" do
    use_transport(->(_uri, **) { raise Net::OpenTimeout })
    get "/courses/#{courses(:rails_course).id}/guest_instructor", headers: auth_headers_for(users(:alice))

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal false, json["available"]
    assert_nil json["instructor"]
  end

  test "exige autenticacao" do
    get "/courses/#{courses(:rails_course).id}/guest_instructor"
    assert_response :unauthorized
  end

  test "curso inexistente responde 404" do
    get "/courses/999999/guest_instructor", headers: auth_headers_for(users(:alice))
    assert_response :not_found
  end
end
