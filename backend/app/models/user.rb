class User < ApplicationRecord
  has_secure_password

  has_many :created_courses, class_name: "Course", foreign_key: "creator_id", dependent: :destroy

  # "Alice@Example.com " e "alice@example.com" são a mesma conta.
  # normalizes também vale para buscas (find_by / authenticate_by).
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 6 }
end
