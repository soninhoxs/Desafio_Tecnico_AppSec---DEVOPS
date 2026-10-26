require "test_helper"

class CourseTest < ActiveSupport::TestCase
  def setup
    @creator = users(:alice)
    @valid_attrs = {
      name: "Desenvolvimento Web",
      description: "Aprenda do zero",
      start_date: Date.today,
      end_date: Date.today + 30,
      creator: @creator
    }
  end

  # ─── Validações de name ──────────────────────────────────────────────────

  test "valido com atributos corretos" do
    assert Course.new(@valid_attrs).valid?
  end

  test "invalido sem nome" do
    course = Course.new(@valid_attrs.merge(name: nil))
    assert_not course.valid?
    assert_includes course.errors[:name], "can't be blank"
  end

  test "invalido com nome de 2 caracteres" do
    course = Course.new(@valid_attrs.merge(name: "AB"))
    assert_not course.valid?
    assert course.errors[:name].any?
  end

  test "valido com nome de exatamente 3 caracteres" do
    assert Course.new(@valid_attrs.merge(name: "ABC")).valid?
  end

  # ─── Validações de datas ─────────────────────────────────────────────────

  test "invalido sem start_date" do
    course = Course.new(@valid_attrs.merge(start_date: nil))
    assert_not course.valid?
    assert course.errors[:start_date].any?
  end

  test "invalido sem end_date" do
    course = Course.new(@valid_attrs.merge(end_date: nil))
    assert_not course.valid?
    assert course.errors[:end_date].any?
  end

  test "invalido quando end_date e anterior a start_date" do
    course = Course.new(@valid_attrs.merge(start_date: Date.today, end_date: Date.today - 1))
    assert_not course.valid?
    assert course.errors[:end_date].any?
  end

  test "valido quando end_date e igual a start_date" do
    assert Course.new(@valid_attrs.merge(start_date: Date.today, end_date: Date.today)).valid?
  end

  test "valido quando end_date e posterior a start_date" do
    assert Course.new(@valid_attrs.merge(start_date: Date.today, end_date: Date.today + 7)).valid?
  end

  # ─── description é opcional ──────────────────────────────────────────────

  test "valido sem descricao" do
    assert Course.new(@valid_attrs.merge(description: nil)).valid?
  end

  test "invalido com nome ou descricao longos demais" do
    assert_not Course.new(@valid_attrs.merge(name: "a" * 151)).valid?
    assert_not Course.new(@valid_attrs.merge(description: "a" * 5001)).valid?
  end

  # ─── Associações ─────────────────────────────────────────────────────────

  test "pertence ao criador correto" do
    assert_equal @creator, courses(:rails_course).creator
  end

  test "destroy apaga lessons em cascata" do
    course = Course.create!(@valid_attrs)
    Lesson.create!(title: "Aula Cascata", status: "draft", course: course)
    assert_difference "Lesson.count", -1 do
      course.destroy
    end
  end
end
