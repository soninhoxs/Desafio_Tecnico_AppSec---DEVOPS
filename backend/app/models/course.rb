class Course < ApplicationRecord
  belongs_to :creator, class_name: "User"
  has_many :lessons, dependent: :destroy

  normalizes :name, with: ->(name) { name.strip }

  # Limites de tamanho: entrada sem limite vira vetor de abuso (payloads enormes).
  validates :name, presence: true, length: { minimum: 3, maximum: 150 }
  validates :description, length: { maximum: 5000 }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  private

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    if end_date < start_date
      errors.add(:end_date, "deve ser igual ou posterior à data de início")
    end
  end
end