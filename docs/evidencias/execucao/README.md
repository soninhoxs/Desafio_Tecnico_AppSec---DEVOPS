# Evidências da execução automática (E2E)

Gerado automaticamente pelo workflow **E2E** em 2026-10-28 21:43 UTC, commit `7f98f93` — [execução no GitHub Actions](https://github.com/soninhoxs/Desafio_Tecnico_AppSec---DEVOPS/actions/runs/40773586077).
Não edite à mão: cada push na `main` que passa no E2E substitui esta pasta.

Ambiente: `docker compose` no runner do GitHub — Nginx na frente de **2 réplicas da API** (`api-1`, `api-2`),
PostgreSQL, Prometheus, Alertmanager e Grafana. A versão original roda a partir da tag `v0-original`.
Tokens JWT foram removidos dos arquivos (`<jwt-removido>`).

## 1. Vulnerabilidades — versão original × corrigida (`security/poc/poc.py`)

| ID | Achado | Versão original (`v0-original`) | Versão corrigida |
|---|---|---|---|
| CONTROLE | Editar/excluir curso de outro criador (IDOR) | **PROTEGIDO** | **PROTEGIDO** |
| VULN-01 | Aula em rascunho visível para outro usuário | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-02 | JWT continua válido após logout | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-03 | Sem proteção contra força bruta no login | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-04 | Credenciais padrão do seed (tech@coursesphere.com / password123) | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-05 | Modo development exposto (stack trace / /rails/info) | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-06 | video_url aceita javascript: (XSS armazenado latente) | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-08 | Enumeração de usuários pelo tempo do login | **VULNERÁVEL** | **CORRIGIDO** |
| VULN-09 | Senha fraca aceita no cadastro ('123456') | **VULNERÁVEL** | **CORRIGIDO** |

<details><summary>Evidência de cada teste (requisição → resposta)</summary>

- **CONTROLE — versão original:** PUT -> 403, DELETE -> 403 (esperado 403)
- **CONTROLE — versão corrigida:** PUT -> 403, DELETE -> 403 (esperado 403)
- **VULN-01 — versão original:** outro usuário: GET /courses/5/lessons -> 200 (rascunho na lista: True); GET /lessons/14 -> 200
- **VULN-01 — versão corrigida:** outro usuário: GET /courses/5/lessons -> 200 (rascunho na lista: False); GET /lessons/14 -> 404
- **VULN-02 — versão original:** DELETE /logout -> 200; GET /me com o mesmo token -> 200
- **VULN-02 — versão corrigida:** DELETE /logout -> 200; GET /me com o mesmo token -> 401
- **VULN-03 — versão original:** 12 senhas erradas -> [401, 401, 401, 401, 401, 401, 401, 401, 401, 401, 401, 401]; senha correta em seguida -> 200 (429 = rate limit; 401 = conta bloqueada)
- **VULN-03 — versão corrigida:** 12 senhas erradas -> [429, 429, 429, 429, 429, 429, 429, 429, 429, 429, 429, 429]; senha correta em seguida -> 429 (429 = rate limit; 401 = conta bloqueada)
- **VULN-04 — versão original:** POST /login -> 200
- **VULN-04 — versão corrigida:** POST /login -> 401
- **VULN-05 — versão original:** GET /rails/info/properties -> 406 (aberto: False); GET /lessons/999999999 -> 404 (stack trace na resposta: True)
- **VULN-05 — versão corrigida:** GET /rails/info/properties -> 404 (aberto: False); GET /lessons/999999999 -> 404 (stack trace na resposta: False)
- **VULN-06 — versão original:** POST lesson com video_url=javascript:... -> 201
- **VULN-06 — versão corrigida:** POST lesson com video_url=javascript:... -> 422
- **VULN-08 — versão original:** mediana e-mail existente = 175 ms; e-mail inexistente = 4 ms
- **VULN-08 — versão corrigida:** mediana e-mail existente = 263 ms; e-mail inexistente = 248 ms
- **VULN-09 — versão original:** POST /signup com senha 123456 -> 201
- **VULN-09 — versão corrigida:** POST /signup com senha 123456 -> 422

</details>

## 2. Balanceamento de carga entre as réplicas

Requisições feitas pelo balanceador (`scripts/lb_demo.py`, header `X-Served-By`):

```text
  api-1     11 req  ###########
  api-2      9 req  #########

OK: as requisições foram distribuídas entre as réplicas.
```

Total de requisições atendidas por réplica, segundo o Prometheus:

| Réplica | Requisições |
|---|---|
| api-1 | 76 |
| api-2 | 72 |

Trecho do log JSON do Nginx (o campo `upstream` mostra a réplica que atendeu):

```json
{"ts":"2026-10-28T21:42:27+00:00","event":"lb_access","request_id":"20363aa934da4b5caf2a07e975357230","remote_addr":"172.18.0.1","method":"GET","uri":"/dashboard","status":304,"bytes":0,"request_time":0.000,"upstream":"172.20.0.2:8080","upstream_status":"304","upstream_response_time":"0.000","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/156.0.8078.4 Safari/537.36"}
{"ts":"2026-10-28T21:42:27+00:00","event":"lb_access","request_id":"86f94d9ab152f6fc962551628c05fd93","remote_addr":"172.18.0.1","method":"GET","uri":"/api/me","status":200,"bytes":73,"request_time":0.003,"upstream":"172.18.0.5:3000","upstream_status":"200","upstream_response_time":"0.004","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/156.0.8078.4 Safari/537.36"}
{"ts":"2026-10-28T21:42:27+00:00","event":"lb_access","request_id":"cd342e3f22e55f32a8b21d0eeb3b8029","remote_addr":"172.18.0.1","method":"GET","uri":"/api/courses","status":200,"bytes":1936,"request_time":0.008,"upstream":"172.18.0.6:3000","upstream_status":"200","upstream_response_time":"0.007","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/156.0.8078.4 Safari/537.36"}
{"ts":"2026-10-28T21:42:27+00:00","event":"lb_access","request_id":"840079d90d2402a9d5fd84708ebac3e9","remote_addr":"172.18.0.1","method":"GET","uri":"/api/courses/6","status":200,"bytes":211,"request_time":0.007,"upstream":"172.18.0.5:3000","upstream_status":"200","upstream_response_time":"0.006","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/156.0.8078.4 Safari/537.36"}
{"ts":"2026-10-28T21:42:27+00:00","event":"lb_access","request_id":"4c4f3d17a96010776c6952d01e4132b6","remote_addr":"172.18.0.1","method":"GET","uri":"/api/courses/6/lessons","status":200,"bytes":2,"request_time":0.008,"upstream":"172.18.0.5:3000","upstream_status":"200","upstream_response_time":"0.009","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/156.0.8078.4 Safari/537.36"}
{"ts":"2026-10-28T21:42:28+00:00","event":"lb_access","request_id":"0cb2bd66fa6483889eb2e200fab8d313","remote_addr":"172.18.0.1","method":"GET","uri":"/api/courses/6/guest_instructor","status":200,"bytes":163,"request_time":0.100,"upstream":"172.18.0.6:3000","upstream_status":"200","upstream_response_time":"0.100","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/156.0.8078.4 Safari/537.36"}
```

## 3. Tratamento de falhas da dependência externa (timeout, retry, circuit breaker)

Saída de `bin/rails runner script/resilience_drill.rb` dentro do container `api-1`:

```text
== 1. Dependência disponível (chamada real à randomuser.me)
  chamada 1:    124 ms  origem=network  disponível=true
  chamada 2:      0 ms  origem=cache    disponível=true

== 2. Dependência fora do ar (IP sem resposta)
   timeouts: conexão 0.5s, leitura 1.5s; 3 tentativas; orçamento 3.0s; disjuntor abre com 5 falhas seguidas e fica aberto 30s
  requisição 1:   2195 ms  resultado=error         disponível=false disjuntor=closed
  requisição 2:   1999 ms  resultado=error         disponível=false disjuntor=closed
  requisição 3:   2267 ms  resultado=error         disponível=false disjuntor=closed
  requisição 4:   2091 ms  resultado=error         disponível=false disjuntor=closed
  requisição 5:   1877 ms  resultado=error         disponível=false disjuntor=open
  requisição 6:      0 ms  resultado=circuit_open  disponível=false disjuntor=open
  requisição 7:      0 ms  resultado=circuit_open  disponível=false disjuntor=open
  requisição 8:      0 ms  resultado=circuit_open  disponível=false disjuntor=open

Conclusão: com a dependência fora do ar, cada requisição fica limitada ao orçamento de tempo até o
disjuntor abrir; a partir daí a resposta é imediata (fallback) e as threads do Puma ficam livres.
```

## 4. Prints

**Aplicação: lista de cursos após o login (usuário de demonstração).**

![app-cursos.png](app-cursos.png)

**Página do curso; o card do instrutor convidado vem da API (`/api/courses/:id/guest_instructor`).**

![app-curso-instrutor.png](app-curso-instrutor.png)

**Grafana: SLOs, requisições por réplica (balanceamento), erros, latência, segurança e dependência externa.**

![grafana-dashboard.png](grafana-dashboard.png)

## 5. Cabeçalhos de segurança do frontend

```http
HTTP/1.1 200 OK
Server: nginx
Date: Wed, 28 Oct 2026 21:43:35 GMT
Content-Type: text/html
Content-Length: 465
Connection: keep-alive
Last-Modified: Wed, 28 Oct 2026 21:38:45 GMT
ETag: "6ae26b65-1d1"
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https://randomuser.me; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()
Cross-Origin-Opener-Policy: same-origin
Cache-Control: no-cache
Accept-Ranges: bytes
```

## 6. DAST — OWASP ZAP baseline (passivo, sem autenticação)

| Risco | Alertas | Itens |
|---|---|---|
| High | 0 | — |
| Medium | 0 | — |
| Low | 2 | Cross-Origin-Embedder-Policy Header Missing or Invalid, Cross-Origin-Resource-Policy Header Missing or Invalid |
| Informational | 4 | Information Disclosure - Suspicious Comments, Modern Web Application, Storable and Cacheable Content, Storable but Non-Cacheable Content |

Relatório completo: [`zap-baseline.md`](zap-baseline.md).

## Arquivos

- [`app-curso-instrutor.png`](app-curso-instrutor.png)
- [`app-cursos.png`](app-cursos.png)
- [`balanceamento-lb-demo.txt`](balanceamento-lb-demo.txt)
- [`balanceamento-log-nginx.txt`](balanceamento-log-nginx.txt)
- [`compose-ps.txt`](compose-ps.txt)
- [`grafana-dashboard.png`](grafana-dashboard.png)
- [`headers-api.txt`](headers-api.txt)
- [`headers-frontend.txt`](headers-frontend.txt)
- [`logs-api-json.txt`](logs-api-json.txt)
- [`metrics-bloqueado-na-borda.txt`](metrics-bloqueado-na-borda.txt)
- [`poc-versao-corrigida.json`](poc-versao-corrigida.json)
- [`poc-versao-corrigida.txt`](poc-versao-corrigida.txt)
- [`poc-versao-original.json`](poc-versao-original.json)
- [`poc-versao-original.txt`](poc-versao-original.txt)
- [`prometheus-dependencia-externa.json`](prometheus-dependencia-externa.json)
- [`prometheus-eventos-seguranca.json`](prometheus-eventos-seguranca.json)
- [`prometheus-requests-por-instancia.json`](prometheus-requests-por-instancia.json)
- [`prometheus-targets.json`](prometheus-targets.json)
- [`resiliencia-circuit-breaker.txt`](resiliencia-circuit-breaker.txt)
- [`zap-baseline.json`](zap-baseline.json)
- [`zap-baseline.md`](zap-baseline.md)
