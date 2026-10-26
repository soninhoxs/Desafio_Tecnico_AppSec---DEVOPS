class Lesson < ApplicationRecord
  STATUSES = %w[draft published].freeze
  ALLOWED_URL_SCHEMES = %w[http https].freeze

  belongs_to :course

  normalizes :title, with: ->(title) { title.strip }
  normalizes :video_url, with: ->(url) { url.strip }

  validates :title, presence: true, length: { minimum: 3, maximum: 150 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :video_url, length: { maximum: 2048 }, allow_blank: true
  validate :video_url_must_be_http_url

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

  private

  # Allowlist de esquema (http/https) com parse real da URL.
  # A validação antiga usava URI::DEFAULT_PARSER.make_regexp, uma regex SEM
  # âncoras que aceita qualquer esquema — inclusive "javascript:alert(1)" —
  # e qualquer texto que apenas CONTENHA algo parecido com uma URI.
  def video_url_must_be_http_url
    return if video_url.blank?

    uri = URI.parse(video_url)
    valid = uri.is_a?(URI::HTTP) &&
      ALLOWED_URL_SCHEMES.include?(uri.scheme.to_s.downcase) &&
      uri.host.to_s.include?(".") &&
      uri.userinfo.nil?
    errors.add(:video_url, "deve ser uma URL http(s) válida") unless valid
  rescue URI::InvalidURIError
    errors.add(:video_url, "deve ser uma URL http(s) válida")
  end
end
