class User < ApplicationRecord
  MAX_FAILED_LOGINS = 5
  LOCKOUT_PERIOD = 15.minutes

  has_secure_password

  has_many :created_courses, class_name: "Course", foreign_key: "creator_id", dependent: :destroy

  # "Alice@Example.com " e "alice@example.com" são a mesma conta.
  # normalizes também vale para buscas (find_by / authenticate_by).
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 6 }

  def locked?
    locked_until.present? && locked_until.future?
  end

  # Incremento atômico no banco: correto mesmo com várias réplicas da API
  # recebendo tentativas em paralelo. Ao atingir o limite, bloqueia por
  # LOCKOUT_PERIOD (bloqueio temporário, para não virar negação de serviço
  # permanente contra a vítima).
  def register_failed_login!
    self.class.where(id: id).update_all("failed_login_attempts = failed_login_attempts + 1")
    reload
    return false if failed_login_attempts < MAX_FAILED_LOGINS

    update_columns(locked_until: LOCKOUT_PERIOD.from_now, failed_login_attempts: 0)
    true
  end

  def register_successful_login!
    return if failed_login_attempts.zero? && locked_until.nil?

    update_columns(failed_login_attempts: 0, locked_until: nil)
  end
end
