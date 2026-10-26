require "test_helper"

class LessonsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @alice  = users(:alice)
    @bob    = users(:bob)
    @course = courses(:rails_course)  # criado por alice
    @lesson = lessons(:published_lesson) # pertence a rails_course
  end

  # ─── GET /courses/:course_id/lessons (index) ─────────────────────────────

  test "lista aulas de um curso autenticado" do
    get "/courses/#{@course.id}/lessons", headers: auth_headers_for(@alice)
    assert_response :ok
    assert_instance_of Array, JSON.parse(response.body)
  end

  test "retorna 401 sem autenticacao ao listar aulas" do
    get "/courses/#{@course.id}/lessons"
    assert_response :unauthorized
  end

  # ─── GET /lessons/:id (show) ──────────────────────────────────────────────

  test "exibe aula existente" do
    get "/lessons/#{@lesson.id}", headers: auth_headers_for(@alice)
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal @lesson.title, json["title"]
  end

  # ─── VULN-01: rascunhos só para o criador do curso ───────────────────────

  test "nao-criador nao ve rascunhos na listagem de aulas" do
    draft = lessons(:draft_lesson) # react_course, criado por bob
    get "/courses/#{draft.course_id}/lessons", headers: auth_headers_for(@alice)
    assert_response :ok
    ids = JSON.parse(response.body).map { |l| l["id"] }
    assert_not_includes ids, draft.id
  end

  test "criador ve os proprios rascunhos na listagem" do
    draft = lessons(:draft_lesson)
    get "/courses/#{draft.course_id}/lessons", headers: auth_headers_for(@bob)
    assert_response :ok
    ids = JSON.parse(response.body).map { |l| l["id"] }
    assert_includes ids, draft.id
  end

  test "nao-criador recebe 404 ao abrir rascunho pelo id" do
    get "/lessons/#{lessons(:draft_lesson).id}", headers: auth_headers_for(@alice)
    assert_response :not_found
  end

  test "criador abre o proprio rascunho pelo id" do
    get "/lessons/#{lessons(:draft_lesson).id}", headers: auth_headers_for(@bob)
    assert_response :ok
  end

  test "nao-criador nao altera nem exclui rascunho de outro (404)" do
    draft = lessons(:draft_lesson)
    patch "/lessons/#{draft.id}", params: { lesson: { title: "Invadido" } },
      headers: auth_headers_for(@alice), as: :json
    assert_response :not_found
    assert_no_difference "Lesson.count" do
      delete "/lessons/#{draft.id}", headers: auth_headers_for(@alice)
    end
    assert_response :not_found
    assert_equal "Conceitos Avancados", draft.reload.title
  end

  test "listar aulas de curso inexistente retorna 404" do
    get "/courses/999999/lessons", headers: auth_headers_for(@alice)
    assert_response :not_found
  end

  # ─── POST /courses/:course_id/lessons (create) ───────────────────────────

  test "criador do curso cria aula valida" do
    params = { lesson: { title: "Nova Aula de Teste", status: "draft" } }
    assert_difference "Lesson.count", 1 do
      post "/courses/#{@course.id}/lessons",
        params: params,
        headers: auth_headers_for(@alice),
        as: :json
    end
    assert_response :created
    assert_equal "Nova Aula de Teste", JSON.parse(response.body)["title"]
  end

  test "nao-criador nao pode criar aula no curso (403)" do
    params = { lesson: { title: "Aula do Bob", status: "draft" } }
    assert_no_difference "Lesson.count" do
      post "/courses/#{@course.id}/lessons",
        params: params,
        headers: auth_headers_for(@bob),
        as: :json
    end
    assert_response :forbidden
  end

  test "nao cria aula com titulo menor que 3 chars (422)" do
    params = { lesson: { title: "AB", status: "draft" } }
    assert_no_difference "Lesson.count" do
      post "/courses/#{@course.id}/lessons",
        params: params,
        headers: auth_headers_for(@alice),
        as: :json
    end
    assert_response :unprocessable_entity
    assert JSON.parse(response.body).key?("errors")
  end

  test "nao cria aula com status invalido (422)" do
    params = { lesson: { title: "Aula Invalida", status: "archived" } }
    assert_no_difference "Lesson.count" do
      post "/courses/#{@course.id}/lessons",
        params: params,
        headers: auth_headers_for(@alice),
        as: :json
    end
    assert_response :unprocessable_entity
  end

  test "cria aula com video_url valida" do
    params = { lesson: {
      title: "Aula com Video",
      status: "published",
      video_url: "https://youtube.com/watch?v=test123"
    } }
    post "/courses/#{@course.id}/lessons",
      params: params,
      headers: auth_headers_for(@alice),
      as: :json
    assert_response :created
  end

  test "nao cria aula com video_url invalida (422)" do
    params = { lesson: {
      title: "Aula Video Ruim",
      status: "draft",
      video_url: "nao-e-url"
    } }
    assert_no_difference "Lesson.count" do
      post "/courses/#{@course.id}/lessons",
        params: params,
        headers: auth_headers_for(@alice),
        as: :json
    end
    assert_response :unprocessable_entity
  end

  test "API recusa video_url com javascript: (VULN-06)" do
    params = { lesson: { title: "Aula XSS", status: "published", video_url: "javascript:alert(document.domain)" } }
    assert_no_difference "Lesson.count" do
      post "/courses/#{@course.id}/lessons", params: params, headers: auth_headers_for(@alice), as: :json
    end
    assert_response :unprocessable_entity
  end

  # ─── PUT /lessons/:id (update) ────────────────────────────────────────────

  test "criador atualiza aula com sucesso" do
    patch "/lessons/#{@lesson.id}",
      params: { lesson: { title: "Titulo Atualizado", status: "published" } },
      headers: auth_headers_for(@alice),
      as: :json
    assert_response :ok
    assert_equal "Titulo Atualizado", JSON.parse(response.body)["title"]
  end

  test "nao-criador nao pode atualizar aula (403)" do
    patch "/lessons/#{@lesson.id}",
      params: { lesson: { title: "Tentativa do Bob" } },
      headers: auth_headers_for(@bob),
      as: :json
    assert_response :forbidden
  end

  # ─── DELETE /lessons/:id (destroy) ───────────────────────────────────────

  test "criador pode excluir aula" do
    lesson_to_delete = Lesson.create!(title: "Deletar isso", status: "draft", course: @course)
    assert_difference "Lesson.count", -1 do
      delete "/lessons/#{lesson_to_delete.id}", headers: auth_headers_for(@alice)
    end
    assert_response :no_content
  end

  test "nao-criador nao pode excluir aula (403)" do
    assert_no_difference "Lesson.count" do
      delete "/lessons/#{@lesson.id}", headers: auth_headers_for(@bob)
    end
    assert_response :forbidden
  end

  test "retorna 401 ao deletar sem autenticacao" do
    delete "/lessons/#{@lesson.id}"
    assert_response :unauthorized
  end
end
