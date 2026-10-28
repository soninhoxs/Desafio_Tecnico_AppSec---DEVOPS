# Exercício de falha da dependência externa (randomuser.me).
#
#   docker compose exec -T api-1 bin/rails runner script/resilience_drill.rb
#
# Roda dentro do container da API (Linux, imagem de produção) e mede:
#   1. o caminho feliz: chamada real -> resposta -> cache;
#   2. a dependência FORA DO AR (IP que não responde): latência de cada
#      requisição até o circuit breaker abrir e, depois, falha imediata.
# Usa clientes próprios (não mexe no disjuntor nem no cache da réplica).
require "stringio"

def elapsed_ms
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  [ result, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000 ]
end

puts "== 1. Dependência disponível (chamada real à randomuser.me)"
real = GuestInstructorClient.new(cache: ActiveSupport::Cache::MemoryStore.new)
2.times do |i|
  result, ms = elapsed_ms { real.fetch(1) }
  printf "  chamada %d: %6.0f ms  origem=%-8s disponível=%s\n", i + 1, ms, result.source, result.available?
end

puts
puts "== 2. Dependência fora do ar (IP sem resposta)"
puts "   timeouts: conexão #{GuestInstructorClient::OPEN_TIMEOUT}s, leitura #{GuestInstructorClient::READ_TIMEOUT}s; " \
     "#{GuestInstructorClient::MAX_ATTEMPTS} tentativas; orçamento #{GuestInstructorClient::TOTAL_BUDGET}s; " \
     "disjuntor abre com 5 falhas seguidas e fica aberto 30s"
blackhole = lambda do |uri, open_timeout:, read_timeout:|
  Net::HTTP.start("10.255.255.1", 443, use_ssl: true, open_timeout: open_timeout, read_timeout: read_timeout) do |http|
    http.get(uri.request_uri)
  end
end
down = GuestInstructorClient.new(transport: blackhole, cache: ActiveSupport::Cache::MemoryStore.new)
8.times do |i|
  result, ms = elapsed_ms { down.fetch(100 + i) }
  printf "  requisição %d: %6.0f ms  resultado=%-13s disponível=%-5s disjuntor=%s\n",
         i + 1, ms, result.source, result.available?, down.state
end

puts
puts "Conclusão: com a dependência fora do ar, cada requisição fica limitada ao orçamento de tempo até o"
puts "disjuntor abrir; a partir daí a resposta é imediata (fallback) e as threads do Puma ficam livres."
