require "test_helper"

class UserTest < ActiveSupport::TestCase
  # ─── Validações ───────────────────────────────────────────────────────────

  test "valido com atributos corretos" do
    user = User.new(name: "Joao", email: "joao@example.com", password: "Senha-Forte-2026")
    assert user.valid?, "Esperava valido, mas erros: #{user.errors.full_messages}"
  end

  test "invalido sem nome" do
    user = User.new(email: "teste@example.com", password: "Senha-Forte-2026")
    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test "invalido sem email" do
    user = User.new(name: "Maria", password: "Senha-Forte-2026")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalido com email malformado" do
    user = User.new(name: "Maria", email: "nao-e-email", password: "Senha-Forte-2026")
    assert_not user.valid?
    assert user.errors[:email].any?
  end

  test "invalido com email duplicado" do
    # alice ja existe nos fixtures
    user = User.new(name: "Copia", email: "alice@example.com", password: "Senha-Forte-2026")
    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "invalido com senha curta (menos de 12 chars)" do
    user = User.new(name: "Carlos", email: "carlos@example.com", password: "Curta#2026")
    assert_not user.valid?
    assert user.errors[:password].any?
  end

  # ─── VULN-09: política de senha ──────────────────────────────────────────

  test "rejeita senhas fracas aceitas pela politica antiga" do
    %w[123456 senha123 password123].each do |weak|
      user = User.new(name: "Fraca", email: "fraca@example.com", password: weak)
      assert_not user.valid?, "#{weak} deveria ser rejeitada"
    end
  end

  test "rejeita senha comum mesmo com 12+ caracteres" do
    user = User.new(name: "Comum", email: "comum@example.com", password: "Password1234")
    assert_not user.valid?
    assert_includes user.errors[:password], "é muito comum ou fácil de adivinhar"
  end

  test "rejeita senha com caractere repetido" do
    assert_not User.new(name: "Rep", email: "rep@example.com", password: "aaaaaaaaaaaaaa").valid?
  end

  test "rejeita senha que contem o proprio email" do
    user = User.new(name: "Maria", email: "mariasilva@example.com", password: "mariasilva2026!")
    assert_not user.valid?
    assert_includes user.errors[:password], "não pode conter o seu e-mail"
  end

  test "aceita frase-senha longa" do
    assert User.new(name: "Ana", email: "ana@example.com", password: "cavalo bateria grampo correto").valid?
  end

  test "atualizar outros campos nao exige reenviar a senha" do
    user = users(:alice)
    assert user.update(name: "Alice Atualizada")
  end

  # ─── Autenticação ─────────────────────────────────────────────────────────

  test "autentica com senha correta" do
    user = users(:alice)
    assert user.authenticate("password123")
  end

  test "nao autentica com senha errada" do
    user = users(:alice)
    assert_not user.authenticate("senha_errada")
  end

  # ─── Associações ─────────────────────────────────────────────────────────

  test "tem muitos cursos criados" do
    assert_includes users(:alice).created_courses, courses(:rails_course)
  end

  test "destroy apaga cursos em cascata" do
    user = User.create!(name: "Temp", email: "temp@example.com", password: "Senha-Forte-2026")
    Course.create!(name: "Temp Course", start_date: Date.today, end_date: Date.today + 1, creator: user)
    assert_difference "Course.count", -1 do
      user.destroy
    end
  end
end
