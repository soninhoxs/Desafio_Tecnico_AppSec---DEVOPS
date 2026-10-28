# Runbook — Dependência externa falhando (`ExternalDependencyCircuitOpen` / `ExternalDependencyFailing`)

**Impacto:** só o card "Instrutor convidado" da página do curso fica indisponível (fallback). Login, cursos e aulas
continuam funcionando — é exatamente para isso que existe o circuit breaker.

## Como funciona (resumo)

`GET /api/courses/:id/guest_instructor` → `GuestInstructorClient` → `https://randomuser.me/api/`

| Proteção | Valor |
|---|---|
| Timeout de conexão / leitura | 0,5 s / 1,5 s, com teto rígido de 2 s por tentativa |
| Retry | até 3 tentativas, backoff exponencial com jitter, só para timeout, erro de rede e HTTP 429/5xx |
| Orçamento total | 3 s por requisição |
| Circuit breaker | abre com 5 falhas seguidas, fica aberto 30 s, depois testa com 1 chamada (meio-aberto) |
| Cache | 24 h por curso (Solid Cache, compartilhado entre réplicas) |
| Fallback | `200 {"available": false, "instructor": null}` |

## Diagnóstico

1. Grafana → linha **"Dependência externa"**: estado do disjuntor por réplica, resultados (`failure`,
   `short_circuited`, `retry`) e latência.
2. Logs:
   - compose: `docker compose logs api-1 api-2 | grep -E 'circuit_breaker|external.request_failed'`
   - Loki: `{app="coursesphere-api"} | json | event=~"circuit_breaker.state_change|external.request_failed"`
   O campo `error_class` diz se é timeout (`Net::OpenTimeout`, `TransientError`), DNS (`SocketError`) ou resposta
   inválida (`PermanentError`).
3. A dependência está no ar? De dentro do container/pod:
   `docker compose exec api-1 ruby -rnet/http -e 'p Net::HTTP.get_response(URI("https://randomuser.me/api/")).code'`
4. No Kubernetes, confira se a NetworkPolicy `api-egress-external-https` existe (sem ela a API não sai para a
   internet e o disjuntor abre — comportamento esperado do default-deny).

## Mitigação

- **Fora do ar do lado deles:** nada a fazer além de acompanhar; o disjuntor testa sozinho a cada 30 s e fecha
  quando a dependência voltar. O cache continua servindo os cursos já consultados.
- **Bloqueio de rede nosso** (egress, DNS, proxy): corrigir a política/rota; o disjuntor fecha no próximo teste.
- **Latência alta mas respondendo:** se o p95 encostar no teto de 2 s, considerar aumentar o cache ou desligar o
  card temporariamente — nunca aumentar os timeouts sem rever o orçamento das threads do Puma.

## Exercício de falha

`docker compose exec -T api-1 bin/rails runner script/resilience_drill.rb` simula a dependência fora do ar e
mostra a latência até o disjuntor abrir e o "falha rápido" depois. O E2E roda esse exercício e publica a saída
em `docs/evidencias/execucao/`.
