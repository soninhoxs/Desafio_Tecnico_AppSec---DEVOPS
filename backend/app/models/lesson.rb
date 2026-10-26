class Lesson < ApplicationRecord
  STATUSES = %w[draft published].freeze

  belongs_to :course

  # Validações obrigatórias
  validates :title, presence: true, length: { minimum: 3 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Validação de formato de URL apenas se o campo não estiver vazio
  validates :video_url, format: { with: URI::DEFAULT_PARSER.make_regexp, message: "deve ser uma URL válida" }, allow_blank: true

  scope :published, -> { where(status: "published") }

  # Aulas que um usuário pode LER.
  # Rascunho é conteúdo ainda não publicado: só o criador do curso pode vê-lo.
  # Toda leitura de aulas deve passar por este escopo (negação por padrão).
  def self.visible_to(user)
    return none unless user

    with_course = joins(:course)
    with_course.where(status: "published").or(with_course.where(courses: { creator_id: user.id }))
  end

  def published?
    status == "published"
  end
end
