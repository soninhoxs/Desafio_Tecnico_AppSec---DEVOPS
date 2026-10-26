# Tabela do Solid Cache no banco principal (antes exigia um banco "cache"
# separado que não existia em produção). É o store compartilhado do rate
# limiting entre as réplicas da API.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cache_entries do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false
    end
    add_index :solid_cache_entries, :byte_size
    add_index :solid_cache_entries, [ :key_hash, :byte_size ]
    add_index :solid_cache_entries, :key_hash, unique: true
  end
end
