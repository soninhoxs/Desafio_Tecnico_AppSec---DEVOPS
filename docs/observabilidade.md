# Observabilidade e SLOs

Como o CourseSphere é monitorado: o que é medido, quais são as metas (SLOs), como ver no Grafana e o que dispara alerta.

## 1. Sinais coletados

| Sinal | Onde nasce | Como acessar |
|---|---|---|
| **Logs JSON da API** (1 linha por requisição + eventos de segurança + erros) | `lib/observability/request_telemetry.rb`, `security_events.rb` | `docker compose logs api-1 api-2` · Loki/Grafana no Kubernetes |
| **Logs JSON do balanceador** (inclui qual réplica atendeu: `upstream`) | `deploy/compose/nginx/nginx.conf` | `docker compose logs lb` |
| **Métricas Prometheus** | `GET /metrics` em cada réplica (token `METRICS_TOKEN`) | Prometheus `:9090`, Grafana `:3001` |
| **Health checks** | `GET /health/live`, `/health/ready`, `/health` | balanceador, Docker, probes do Kubernetes |

Exemplo de log de requisição (produção):

```json
{"ts":"2026-10-26T18:52:44.939Z","level":"INFO","service":"coursesphere-api","instance":"api-2",
 "event":"http_request","method":"GET","path":"/courses/12","route":"/courses/:id","status":200,
 "duration_ms":8.41,"request_id":"6c1f0d2e9b8a4c1f","user_id":7,"remote_ip":"172.20.0.1","user_agent":"Mozilla/5.0 ..."}
```

Exemplo de evento de segurança:

```json
{"ts":"...","level":"WARN","event":"security.login_failure","request_id":"...","remote_ip":"203.0.113.10",
 "path":"/login","user_id":3,"email_fp":"9f2c1a7b0e4d5c6a","known_account":true}
```

> O e-mail nunca vai para o log em claro: `email_fp` é um hash curto que permite correlacionar tentativas contra a mesma conta.

### Métricas expostas

| Métrica | Tipo | Labels | Uso |
|---|---|---|---|
| `http_server_requests_total` | counter | `method`, `route`, `status` | taxa de requisições e erros (SLI-1) |
| `http_server_request_duration_seconds` | histogram | `method`, `route` | latência (SLI-2, SLI-3) |
| `http_server_requests_in_flight` | gauge | — | saturação |
| `coursesphere_security_events_total` | counter | `event` | força bruta, bloqueios, 403, tokens recusados |
| `coursesphere_db_pool_connections` | gauge | `state` (size/busy/idle/waiting/dead) | saturação do banco |
| `coursesphere_app_info` | gauge | `version`, `instance` | versão em execução por réplica |
| `coursesphere_uptime_seconds` | gauge | — | reinícios |

`route` é o **padrão** da rota (`/courses/:id`), nunca o caminho com IDs. Assim a cardinalidade fica baixa.

## 2. SLIs e SLOs

Janela: **30 dias corridos**.

| | SLI | Meta | Orçamento de erro |
|---|---|---|---|
| **SLO-1 — Disponibilidade do CRUD** | `requisições de /courses* e /lessons* sem 5xx / total` | **99,5%** | 0,5% (≈ 3h36min de "falha total" por mês) |
| **SLO-2 — Latência do login** | `POST /login com duração < 500 ms / total de POST /login` | **99%** | 1% dos logins podem passar de 500 ms |
| **SLO-3 — Latência de leitura** | `GET de cursos/aulas < 250 ms / total` | **99%** | 1% |

**Por que essas metas.** Para um sistema acadêmico de um único banco, 99,5% é realista sem multi-região, e indisponibilidade de alguns minutos não causa perda de dados. O login tem meta própria porque o bcrypt (≈250 ms) já consome metade do limite de 500 ms: qualquer degradação de CPU aparece primeiro aí.

### PromQL (recording rules em `deploy/observability/prometheus/rules/coursesphere.rules.yml`)

```promql
# SLI-1: fração de erro (5xx) do CRUD em 5 min
sum(rate(http_server_requests_total{route=~"/courses.*|/lessons.*",status=~"5.."}[5m]))
/ sum(rate(http_server_requests_total{route=~"/courses.*|/lessons.*"}[5m]))

# SLO-1 atingido nos últimos 30 dias (Grafana)
1 - sum(increase(http_server_requests_total{route=~"/courses.*|/lessons.*",status=~"5.."}[30d]))
  / sum(increase(http_server_requests_total{route=~"/courses.*|/lessons.*"}[30d]))

# SLI-2: fração de logins acima de 500 ms
1 - sum(rate(http_server_request_duration_seconds_bucket{route="/login",le="0.5"}[5m]))
  / sum(rate(http_server_request_duration_seconds_count{route="/login"}[5m]))

# p95 do login
histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{route="/login"}[5m])))
```

## 3. Alertas

Os alertas de SLO usam **burn rate multi-janela** (Google SRE Workbook, cap. 5): disparam quando o orçamento de erro é consumido rápido demais, nas janelas longa **e** curta ao mesmo tempo. Isso evita ruído de picos isolados e ainda detecta rápido um problema real.

| Alerta | Condição | Severidade | Runbook |
|---|---|---|---|
| `CrudErrorBudgetFastBurn` | erro 5xx > 14,4 × 0,5% em 1h **e** em 5min | critical | [api-erros-5xx](runbooks/api-erros-5xx.md) |
| `CrudErrorBudgetSlowBurn` | erro 5xx > 6 × 0,5% em 6h **e** em 30min | warning | [api-erros-5xx](runbooks/api-erros-5xx.md) |
| `LoginLatencySLOBurn` | logins > 500 ms acima de 14,4 × 1% (1h e 5min) | warning | [latencia-alta](runbooks/latencia-alta.md) |
| `ApiInstanceDown` | uma réplica sem responder ao scrape por 1 min | warning | [api-fora-do-ar](runbooks/api-fora-do-ar.md) |
| `ApiAllInstancesDown` | nenhuma réplica respondendo | critical | [api-fora-do-ar](runbooks/api-fora-do-ar.md) |
| `DatabaseConnectionPoolSaturated` | threads esperando conexão por 5 min | warning | [latencia-alta](runbooks/latencia-alta.md) |
| `PossibleBruteForce` | > 30 falhas de login/min por 5 min | warning | [forca-bruta](runbooks/forca-bruta.md) |
| `AccountsBeingLocked` | > 5 contas bloqueadas em 15 min | warning | [forca-bruta](runbooks/forca-bruta.md) |
| `AccessDeniedSpike` | > 20 respostas 403/min por 5 min | info | [forca-bruta](runbooks/forca-bruta.md) |

`ApiAllInstancesDown` inibe `ApiInstanceDown`, para não repetir o mesmo problema em vários alertas.

## 4. Dashboard (Grafana)

O dashboard **"CourseSphere — SLOs, tráfego e segurança"** é provisionado automaticamente (compose: `http://localhost:3001`; Kubernetes: `http://grafana.localhost:8080`). Fonte: `deploy/observability/grafana/dashboards/coursesphere-overview.json`.

| Linha | Painéis | Público |
|---|---|---|
| **SLOs (visão de gestão)** | SLO-1 nos últimos 30 dias (verde ≥ 99,5%), **orçamento de erro restante**, p95 do login vs. 500 ms, réplicas no ar | gestão / plantão |
| **Tráfego e balanceamento** | requisições/s **por réplica** (as linhas de api-1 e api-2 caminham juntas = balanceamento funcionando), requisições/s por status | SRE |
| **Erros e latência** | taxa de 5xx do CRUD com a linha do SLO, p95 por rota, login p50/p95/p99, requisições em andamento e pool do banco | SRE / dev |
| **Segurança** | eventos por tipo (login_failure, account_locked, rate_limited, access_denied, token_rejected), respostas 401/403/429 | segurança |

Logs (Kubernetes): no Grafana → *Explore* → fonte **Loki**, ex.: `{namespace="coursesphere", app="coursesphere-api"} | json | event="security.login_failure"`.

## 5. Como gerar tráfego para ver o dashboard

```bash
python scripts/lb_demo.py -n 200                      # tráfego distribuído entre as réplicas
python security/poc/poc.py --base-url http://localhost:8080/api   # gera eventos de segurança
```
