# Lista de tokens revogados (denylist) para invalidar um JWT antes do exp.
# Fica no PostgreSQL para valer para TODAS as réplicas da API.
class RevokedToken < ApplicationRecord
  scope :expired, -> { where(expires_at: ...Time.current) }

  def self.revoked?(jti)
    jti.present? && exists?(jti: jti)
  end

  # Idempotente: revogar o mesmo token duas vezes não gera erro.
  def self.revoke!(claims)
    expired.delete_all # tokens já expirados não precisam continuar na lista
    insert(
      { jti: claims[:jti], user_id: claims[:user_id], expires_at: Time.zone.at(claims[:exp].to_i) },
      unique_by: :jti
    )
  end
end
