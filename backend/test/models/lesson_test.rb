require "test_helper"

class LessonTest < ActiveSupport::TestCase
  def setup
    @course = courses(:rails_course)
    @valid_attrs = { title: "Introducao ao Ruby", status: "draft", course: @course }
  end

  # ─── Validações de title ─────────────────────────────────────────────────

  test "valido com atributos corretos" do
    assert Lesson.new(@valid_attrs).valid?
  end

  test "invalido sem titulo" do
    lesson = Lesson.new(@valid_attrs.merge(title: nil))
    assert_not lesson.valid?
    assert_includes lesson.errors[:title], "can't be blank"
  end

  test "invalido com titulo de 2 caracteres" do
    lesson = Lesson.new(@valid_attrs.merge(title: "AB"))
    assert_not lesson.valid?
    assert lesson.errors[:title].any?
  end

  test "valido com titulo de exatamente 3 caracteres" do
    assert Lesson.new(@valid_attrs.merge(title: "ABC")).valid?
  end

  # ─── Validações de status ────────────────────────────────────────────────

  test "invalido sem status" do
    lesson = Lesson.new(@valid_attrs.merge(status: nil))
    assert_not lesson.valid?
  end

  test "invalido com status nao permitido" do
    lesson = Lesson.new(@valid_attrs.merge(status: "archived"))
    assert_not lesson.valid?
    assert lesson.errors[:status].any?
  end

  test "valido com status draft" do
    assert Lesson.new(@valid_attrs.merge(status: "draft")).valid?
  end

  test "valido com status published" do
    assert Lesson.new(@valid_attrs.merge(status: "published")).valid?
  end

  # ─── Validações de video_url ─────────────────────────────────────────────

  test "valido sem video_url" do
    assert Lesson.new(@valid_attrs.merge(video_url: nil)).valid?
  end

  test "valido com video_url em branco" do
    assert Lesson.new(@valid_attrs.merge(video_url: "")).valid?
  end

  test "invalido com video_url malformada" do
    lesson = Lesson.new(@valid_attrs.merge(video_url: "nao-e-uma-url"))
    assert_not lesson.valid?
    assert lesson.errors[:video_url].any?
  end

  test "valido com video_url http correta" do
    assert Lesson.new(@valid_attrs.merge(video_url: "https://youtube.com/watch?v=abc123")).valid?
  end

  # ─── VULN-06: só http/https ──────────────────────────────────────────────

  [
    "javascript:alert(document.domain)",
    "JaVaScRiPt:alert(1)",
    "data:text/html,<script>alert(1)</script>",
    "vbscript:msgbox(1)",
    "texto qualquer http://exemplo.com",
    "ftp://exemplo.com/video.mp4",
    "https://usuario:senha@exemplo.com/video",
    "https://localhost/video"
  ].each do |url|
    test "rejeita video_url perigosa ou invalida: #{url}" do
      lesson = Lesson.new(@valid_attrs.merge(video_url: url))
      assert_not lesson.valid?, "#{url} deveria ser rejeitada"
      assert lesson.errors[:video_url].any?
    end
  end

  test "remove espacos nas pontas da video_url" do
    lesson = Lesson.new(@valid_attrs.merge(video_url: "  https://www.youtube.com/watch?v=x  "))
    assert lesson.valid?
    assert_equal "https://www.youtube.com/watch?v=x", lesson.video_url
  end

  test "rejeita titulo muito longo" do
    assert_not Lesson.new(@valid_attrs.merge(title: "a" * 151)).valid?
  end

  # ─── Associações ─────────────────────────────────────────────────────────

  test "pertence ao curso correto" do
    assert_equal @course, lessons(:published_lesson).course
  end
end
