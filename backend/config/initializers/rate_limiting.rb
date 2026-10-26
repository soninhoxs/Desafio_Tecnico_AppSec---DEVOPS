# Store usado pelo rate limiting dos controllers (ActionController::RateLimiting).
#
# Em produção é o Rails.cache = Solid Cache, guardado no PostgreSQL: o limite
# vale para o sistema todo, e não por réplica. Com um MemoryStore por
# processo, 2 réplicas atrás do balanceador dobrariam o limite efetivo.
# Em dev/test um MemoryStore basta (e o test env usa :null_store no Rails.cache,
# que desligaria o limite).
module RateLimiting
  LOGIN_LIMIT = { to: 10, within: 1.minute }.freeze
  SIGNUP_LIMIT = { to: 10, within: 10.minutes }.freeze

  def self.store
    @store ||= Rails.env.production? ? Rails.cache : ActiveSupport::Cache::MemoryStore.new
  end
end
