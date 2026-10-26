# Relatório Técnico — Pentest e Confiabilidade do CourseSphere

| | |
|---|---|
| **Alvo** | CourseSphere — API Ruby on Rails 8.1 + frontend React 19 (gestão de cursos e aulas) |
| **Versão analisada** | commit `2035d25`, marcada no Git como **`v0-original`** |
| **Versão corrigida** | branch `main` deste repositório |
| **Período** | outubro de 2026 |
| **Ambiente de teste** | local e isolado (docker compose / cluster kind). Nenhum teste contra sistemas de terceiros. |
| **Referências** | OWASP Top 10:2025, OWASP ASVS 5.0, OWASP WSTG, CVSS 3.1, Google SRE Workbook |

---

## 1. Sumário executivo (para gestão)

Foram encontradas **9 vulnerabilidades reais** na aplicação. **Todas foram corrigidas**, com teste automatizado e prova de conceito (PoC) que comprovam a correção. As mais graves:

1. **Qualquer instalação nova nascia com duas contas de instrutor com senha pública** (`password123`, publicada no README). Quem lesse o README podia entrar como instrutor e editar ou apagar os cursos dessas contas.
2. **A aplicação era publicada em modo de desenvolvimento.** Erros devolviam o código-fonte interno (stack trace), páginas de diagnóstico ficavam abertas sem login, e o frontend rodava um servidor de desenvolvimento com falhas conhecidas.
3. **Nada limitava tentativas de login.** Somado a senhas fracas aceitas (`123456`), contas podiam ser descobertas por tentativa e erro.
4. **30 falhas conhecidas em bibliotecas** (1 crítica) e 14 no frontend (11 altas).

O controle de acesso principal ("um usuário não edita o curso de outro") **já funcionava** e foi confirmado por teste. A falha de acesso encontrada estava na **leitura**: aulas em rascunho de qualquer curso eram visíveis para qualquer usuário logado.

| ID | Vulnerabilidade | Severidade (contexto) | CVSS 3.1 | Status |
|---|---|---|---|---|
| VULN-04 | Credenciais padrão criadas em qualquer ambiente | **Alta** | 8.6 | Corrigida |
| VULN-05 | Aplicação publicada em modo de desenvolvimento | **Alta** | 5.3 | Corrigida |
| VULN-03 | Sem proteção contra força bruta no login | **Alta** | 6.5 | Corrigida |
| VULN-07 | Dependências com vulnerabilidades conhecidas | **Média** | 7.4 | Corrigida |
| VULN-01 | Aulas em rascunho visíveis para qualquer usuário | **Média** | 4.3 | Corrigida |
| VULN-02 | Logout não invalida o token de sessão | **Média** | 4.8 | Corrigida |
| VULN-09 | Política de senha fraca | **Média** | 4.8 | Corrigida |
| VULN-06 | Campo de URL aceita `javascript:` (XSS armazenado latente) | **Baixa** | 4.4 | Corrigida |
| VULN-08 | Tempo de resposta do login revela e-mails cadastrados | **Baixa** | 5.3 | Corrigida |

> **Severidade (contexto)** é a classificação usada para priorizar. Ela considera o ambiente real: por exemplo, a VULN-07 tem CVSS alto porque a pior biblioteca tinha falha grave, mas a parte vulnerável não era alcançável nesta aplicação. Já a VULN-05 tem CVSS moderado, mas expunha o sistema inteiro a outras falhas. A justificativa está em cada achado.

**Confiabilidade:** a aplicação original rodava como **uma instância única**, sem health check, sem métricas e sem logs estruturados. Agora roda com **2 réplicas atrás de um balanceador** (Nginx no compose; Traefik no Kubernetes), com health checks, métricas Prometheus, logs JSON, dashboard no Grafana e alertas baseados em **SLOs**. O maior risco de disponibilidade que ainda resta é o **banco de dados único** (seção 8.4).

---

## 2. Escopo

**Em escopo**
- API Rails (`backend/`): autenticação JWT, cursos, aulas, usuários, configuração.
- Frontend React (`frontend/`): uso da API, armazenamento da sessão, renderização de dados do usuário.
- Artefatos de deploy entregues com o projeto: `docker-compose.yml`, Dockerfiles, `entrypoint.sh`, seeds.
- Dependências (Gemfile.lock, package-lock.json) e imagens base.

**Fora de escopo**
- API externa `randomuser.me` (só o *uso* dela pelo frontend foi avaliado).
- Negação de serviço volumétrica, engenharia social e infraestrutura de nuvem real (não existia).

**Regras de engajamento:** todos os testes dinâmicos foram feitos contra instâncias locais criadas para isso (docker compose, kind), com usuários criados pelo próprio teste.

---

## 3. Metodologia

| Etapa | O que foi feito | Ferramentas |
|---|---|---|
| 1. Reconhecimento | Leitura do README, rotas, modelos, fluxo de autenticação e do compose | leitura manual |
| 2. Revisão manual de código | Cada controller, modelo, serviço JWT, seeds, configs de ambiente, CORS, Dockerfiles, frontend (onde o token fica e como dados do usuário são renderizados) | leitura manual |
| 3. SAST | Análise estática do código | **Brakeman 8.1**, **Semgrep 1.182** (rulesets da comunidade + regras próprias) |
| 4. SCA | Dependências com CVEs conhecidas | **bundler-audit**, **npm audit**, **OSV.dev**, **Trivy** |
| 5. Segredos | Histórico Git completo | **Gitleaks 8.30** |
| 6. IaC | Dockerfiles, Kubernetes, Terraform | **Trivy config**, **kubeconform**, **terraform validate**, **promtool**, **actionlint** |
| 7. Testes dinâmicos | Exploração de cada hipótese contra a API em execução | `curl` e **`security/poc/poc.py`** |
| 8. DAST | Varredura passiva da aplicação em execução | **OWASP ZAP baseline** (no CI) |
| 9. Verificação | Correção da causa raiz + teste automatizado + PoC na versão corrigida + regra Semgrep contra regressão | Minitest, PoC, Semgrep |

**Classificação:** cada achado tem o vetor **CVSS 3.1 base** (calculado com a fórmula oficial) e uma **severidade de contexto** (Alta/Média/Baixa), que considera explorabilidade real e impacto no negócio. Mapeamento para **OWASP Top 10:2025** e **CWE**.

### 3.1 O que as ferramentas automáticas encontraram (antes × depois)

| Ferramenta | Versão original | Versão corrigida | Evidência |
|---|---|---|---|
| Brakeman | **0 avisos** | 0 avisos | `docs/evidencias/baseline/brakeman.txt` |
| Semgrep (comunidade) | 10 achados de configuração (Actions sem SHA, container root, Dependabot sem cooldown); **nenhuma das falhas de lógica** | — | `docs/evidencias/baseline/semgrep.txt` |
| Semgrep (regras próprias) | **12 achados** (VULN-01, 02, 04, 05, 06) | **0** | `docs/evidencias/depois/semgrep-regras-proprias.txt` |
| bundler-audit | **30 avisos** (1 crítico) | **0** | `docs/evidencias/{baseline,depois}/bundler-audit.txt` |
| npm audit | **14** (11 altas) | **0** | `docs/evidencias/{baseline,depois}/npm-audit.txt` |
| Trivy (lockfiles) | — | 0 HIGH/CRITICAL | CI `security.yml` |
| Gitleaks | sem segredos no histórico | sem segredos | CI `security.yml` |

> **Lição principal:** o SAST não encontrou **nenhuma** das 6 falhas de lógica (Brakeman: 0 avisos). Elas só apareceram na revisão manual. Por isso, cada uma virou uma **regra Semgrep própria** (`security/semgrep/coursesphere.yml`), que roda no CI e impede que o padrão volte.

---

## 4. Achados detalhados

> **Como reproduzir tudo de uma vez:** suba a versão original (`git checkout v0-original && docker compose up -d --build`) e rode
> `python security/poc/poc.py --base-url http://localhost:3000`. Na versão corrigida:
> `python security/poc/poc.py --base-url http://localhost:8080/api`. O workflow **E2E** do GitHub Actions faz as duas execuções e publica a saída como artefato (`evidencias-versao-original` e `evidencias-versao-corrigida`).
>
> Nos passos manuais abaixo, `API=http://localhost:3000` (original) e `TOKEN_A`/`TOKEN_B` são tokens de dois usuários diferentes, obtidos em `POST /signup` ou `POST /login`.

---

### VULN-01 — Aulas em rascunho visíveis para qualquer usuário autenticado

| | |
|---|---|
| **Severidade** | **Média** — CVSS 3.1 **4.3** `AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N` |
| **Categoria** | OWASP **A01:2025 Broken Access Control** · CWE-639 / CWE-284 |
| **Onde** | `LessonsController#index` e `#show` (`backend/app/controllers/lessons_controller.rb`) |
| **Correção** | commit `cb35745` |

**Descrição.** A regra "só o criador mexe no curso" era aplicada em `create`, `update` e `destroy`, mas **não na leitura**. `GET /courses/:id/lessons` devolvia todas as aulas, inclusive as com `status: "draft"`, e `GET /lessons/:id` devolvia qualquer aula pelo ID. Como os IDs são sequenciais, dava para percorrer todos os rascunhos da plataforma.

**Reprodução.**
```bash
# A cria um curso e uma aula em rascunho
curl -s -X POST $API/courses -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
  -d '{"course":{"name":"Curso A","start_date":"2026-11-01","end_date":"2026-12-01"}}'        # -> {"id": 10, ...}
curl -s -X POST $API/courses/10/lessons -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
  -d '{"lesson":{"title":"Rascunho secreto","status":"draft"}}'                                # -> {"id": 55, ...}

# B (outro usuário) lê o rascunho
curl -s $API/courses/10/lessons -H "Authorization: Bearer $TOKEN_B"   # original: 200, lista contém a aula 55
curl -s $API/lessons/55         -H "Authorization: Bearer $TOKEN_B"   # original: 200 com o conteúdo
```
Corrigido: a listagem não traz o rascunho e `GET /lessons/55` responde **404**.

**Impacto.** Vazamento de conteúdo não publicado: aulas em preparação, material pago ainda não lançado, títulos que revelam a estratégia do curso.

**Causa raiz.** A autorização foi pensada só para escrita. A leitura usava `@course.lessons` e `Lesson.find` sem filtro, ou seja, a regra de visibilidade não existia em lugar nenhum do código.

**Correção.** Criamos o escopo `Lesson.visible_to(user)` (publicada **ou** curso do próprio usuário) e **toda** leitura passa por ele, incluindo a busca usada antes de `update`/`destroy`. Rascunho de outra pessoa responde **404** (e não 403), para não confirmar que a aula existe. Isso resolve a causa porque a visibilidade vira regra de domínio, aplicada na consulta ao banco, e não uma checagem que cada action precisa lembrar de fazer.

**Verificação.** 6 testes novos em `lessons_controller_test.rb` (listagem, show, update e destroy por não-criador; criador continua vendo) + PoC + regra Semgrep `lesson-read-without-visibility-scope`.

---

### VULN-02 — Logout não invalida o token de sessão (JWT)

| | |
|---|---|
| **Severidade** | **Média** — CVSS 3.1 **4.8** `AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N` |
| **Categoria** | OWASP **A07:2025 Authentication Failures** · CWE-613 |
| **Onde** | `AuthenticationController#logout`, `JsonWebToken`, `AuthContext.jsx` |
| **Correção** | commit `076e105` |

**Descrição.** O JWT valia 1 hora e o servidor não guardava estado. O `DELETE /logout` só respondia "Logged out" e o frontend apagava o token do `localStorage`. **O token continuava aceito pela API** até expirar.

**Reprodução.**
```bash
TOKEN=$(curl -s -X POST $API/login -H 'Content-Type: application/json' \
  -d '{"email":"a@exemplo.com","password":"..."}' | jq -r .token)
curl -s -X DELETE $API/logout -H "Authorization: Bearer $TOKEN"   # 200 "Logged out successfully"
curl -s -o /dev/null -w '%{http_code}\n' $API/me -H "Authorization: Bearer $TOKEN"
# original: 200  |  corrigido: 401
```

**Impacto.** Um token vazado (XSS, log, proxy, computador compartilhado) dá acesso à conta por até 1 hora, mesmo que a vítima tenha clicado em "Sair". O usuário não tem como encerrar uma sessão comprometida.

**Causa raiz.** O desenho "JWT stateless sem revogação" não tinha nenhum mecanismo de invalidação. O logout era só cosmético.

**Correção.**
- Cada token ganha um `jti` (UUID). O logout grava o `jti` na tabela `revoked_tokens`, e `authorize_request` recusa tokens revogados. A tabela fica no PostgreSQL, então a revogação vale para **todas as réplicas** da API. Entradas expiradas são limpas automaticamente.
- Validação estrita: algoritmo fixo `HS256`, claims obrigatórias (`exp`, `iat`, `jti`, `user_id`) e chave própria derivada do `secret_key_base` (separação de chaves).
- O frontend passa a chamar `DELETE /logout` ao sair.

**Verificação.** 7 testes novos (token revogado após logout, sessões independentes, `alg: none`, chave errada, token expirado, token sem `jti`) + PoC + regras Semgrep `logout-without-token-revocation` e `jwt-decode-without-explicit-algorithm`.

**Risco residual.** O token ainda fica no `localStorage` (acessível a um XSS). A recomendação R6 (cookie `HttpOnly` + `SameSite`) elimina isso.

---

### VULN-03 — Sem proteção contra força bruta / credential stuffing

| | |
|---|---|
| **Severidade** | **Alta** (contexto) — CVSS 3.1 **6.5** `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N` |
| **Categoria** | OWASP **A07:2025 Authentication Failures** · CWE-307 |
| **Onde** | `POST /login`, `POST /signup` |
| **Correção** | commit `416b854` (+ Nginx/Traefik em `8efbacd` e `6e0e6f4`) |

**Descrição.** Tentativas ilimitadas de login, sem atraso, bloqueio, alerta ou registro.

**Reprodução.**
```bash
for i in $(seq 1 50); do
  curl -s -o /dev/null -w '%{http_code} ' -X POST $API/login -H 'Content-Type: application/json' \
    -d "{\"email\":\"vitima@exemplo.com\",\"password\":\"chute$i\"}"
done
# original: 401 401 401 ... (50x) e a senha certa continua funcionando
# corrigido: 401 x5 (conta bloqueada por 15 min) e depois 429 (rate limit)
```

**Impacto.** Tomada de conta por dicionário ou por senhas vazadas de outros sites (credential stuffing). A severidade de contexto é **Alta** porque se soma às VULN-09 (senha `123456` aceita) e VULN-04 (senha padrão pública).

**Causa raiz.** Não havia nenhum controle de volume no fluxo de autenticação.

**Correção (defesa em camadas).**
1. **Borda:** `limit_req` no Nginx (10/min por IP em `/api/login` e `/api/signup`); `rateLimit` do Traefik no Kubernetes.
2. **Aplicação, por IP:** `rate_limit` nativo do Rails 8 (login 10/min, cadastro 10/10 min, resposta `429` + `Retry-After`). O contador fica no **Solid Cache (PostgreSQL)**, compartilhado entre réplicas. Com um cache em memória por processo, 2 réplicas atrás do balanceador dobrariam o limite.
3. **Aplicação, por conta:** bloqueio temporário de 15 min após 5 falhas seguidas, com incremento atômico no banco. A resposta continua genérica, para não revelar o bloqueio. O bloqueio é **temporário** de propósito: um bloqueio permanente viraria uma forma de derrubar a conta de qualquer pessoa.
4. **Detecção:** cada falha, bloqueio e 429 vira evento de segurança (log JSON + métrica), com alertas `PossibleBruteForce` e `AccountsBeingLocked`.

**Verificação.** 6 testes em `brute_force_protection_test.rb` + PoC.

---

### VULN-04 — Credenciais padrão criadas em qualquer ambiente

| | |
|---|---|
| **Severidade** | **Alta** — CVSS 3.1 **8.6** `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:H/A:L` |
| **Categoria** | OWASP **A07:2025 Authentication Failures** / A02:2025 · CWE-1392, CWE-798 |
| **Onde** | `backend/entrypoint.sh`, `backend/db/seeds.rb`, `README.md` |
| **Correção** | commit `ebdd6e8` |

**Descrição.** O `entrypoint.sh` rodava `rails db:prepare` **em todo start do container e em qualquer ambiente**. Num banco vazio, esse comando executa os seeds, que criavam `tech@coursesphere.com` e `design@coursesphere.com` com a senha `password123`, documentada no README público. O seed também começava com `User.destroy_all`.

**Reprodução.**
```bash
curl -s -X POST $API/login -H 'Content-Type: application/json' \
  -d '{"email":"tech@coursesphere.com","password":"password123"}'
# original: 200 + token de instrutor  |  corrigido: 401
```

**Impacto.** Qualquer pessoa entra como instrutor e altera ou apaga os cursos dessas contas. Num deploy de produção a partir de banco vazio, o problema nasceria em produção. Rodar `db:seed` em produção apagaria **todos os usuários e cursos** (`destroy_all`).

**Causa raiz.** Mistura de responsabilidades: dados de demonstração acoplados ao processo de inicialização de todos os ambientes, com senha fixa no código.

**Correção.**
- Seeds **não rodam em produção** sem `ALLOW_DEMO_SEED=true`, e **não existe senha padrão**: em produção `DEMO_USER_PASSWORD` é obrigatória; em dev/test é aleatória.
- Seeds idempotentes (`find_or_create_by!`), sem `destroy_all`.
- O container não migra mais no start. A migração é um passo único de deploy: serviço `migrate` no compose e Job/hook do ArgoCD no Kubernetes. Isso também elimina a corrida entre réplicas migrando ao mesmo tempo.

**Verificação.** PoC + regras Semgrep `destructive-seed` e `hardcoded-seed-password` + execução dos seeds no CI.

---

### VULN-05 — Aplicação publicada em modo de desenvolvimento (configuração insegura)

| | |
|---|---|
| **Severidade** | **Alta** (contexto) — CVSS 3.1 **5.3** `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N` |
| **Categoria** | OWASP **A02:2025 Security Misconfiguration** · CWE-489, CWE-209, CWE-250, CWE-798 |
| **Onde** | `docker-compose.yml`, `backend/Dockerfile`, `frontend/Dockerfile`, `config/database.yml` |
| **Correção** | commits `386a1ce`, `8efbacd`, `8ca68c5` |

**Descrição.** O único artefato de deploy (docker compose) subia:
- a API com `RAILS_ENV=development`: erros devolvem **exceção e stack trace completos** (caminhos de arquivo, versões de gems). `GET /rails/info/properties` e `/rails/info/routes` ficam abertos **sem autenticação**;
- o frontend como **servidor de desenvolvimento do Vite** exposto (`--host`), com 7 avisos de segurança próprios no `npm audit` (ex.: leitura de arquivos fora do diretório permitido);
- containers como **root**, código montado por volume, `SECRET_KEY_BASE` e senha do banco (`password`) fixos no compose/database.yml.

**Reprodução.**
```bash
curl -s $API/rails/info/properties | head        # original: 200, versões de Ruby/Rails/banco
curl -s $API/lessons/999999999 -H "Authorization: Bearer $TOKEN_A"
# original: 404 com {"status":404,"error":"Not Found","exception":"#<ActiveRecord::RecordNotFound ...>",
#           "traces":{"Application Trace":[...], "Full Trace":[...]}}
# corrigido: 404 {"error":"Lesson not found"}  e /rails/info -> 404
```

**Impacto.** Mapa completo da aplicação para o atacante (rotas, versões, estrutura de arquivos), mais um servidor de desenvolvimento vulnerável exposto. Severidade de contexto **Alta** porque afeta todo o ambiente e potencializa as outras falhas.

**Causa raiz.** Ausência de uma configuração de produção. O compose de desenvolvimento era usado como deploy.

**Correção.**
- Imagens de produção multi-stage: API com `RAILS_ENV=production`, usuário uid **10001**, sem compiladores, rootfs somente leitura. Frontend como build estático servido por **nginx-unprivileged**.
- Segredos fora do Git (`.env` gerado por `scripts/bootstrap_env.py`; Secrets do Kubernetes criados pelo Terraform). `database.yml` sem credenciais.
- `production.rb` corrigido: antes referenciava um banco `queue` que não existia, ou seja, produção nem subia. Adicionados `ALLOWED_HOSTS`, `FORCE_SSL`/HSTS opcional e logs JSON.
- Remoção dos componentes do Rails não usados (Active Storage com rotas públicas de upload, Action Cable, Mailbox etc.).

**Verificação.** PoC + regras Semgrep `rails-development-env-in-compose` e `vite-dev-server-exposed` + Trivy config (0 achados nos Dockerfiles).

---

### VULN-06 — `video_url` aceita `javascript:` (XSS armazenado latente)

| | |
|---|---|
| **Severidade** | **Baixa** (contexto) — CVSS 3.1 **4.4** `AV:N/AC:H/PR:L/UI:R/S:C/C:L/I:L/A:N` |
| **Categoria** | OWASP **A05:2025 Injection** · CWE-79, CWE-20 |
| **Onde** | `Lesson` (`validates :video_url, format: { with: URI::DEFAULT_PARSER.make_regexp }`), `CourseDetails.jsx` |
| **Correção** | commit `72b5674` |

**Descrição.** `URI::DEFAULT_PARSER.make_regexp` gera uma regex **sem âncoras e sem restrição de esquema**. Ela aceita `javascript:alert(document.domain)`, `data:`, `vbscript:` e até texto livre que só *contenha* algo parecido com uma URI. A validação do formulário React é só do lado do cliente e é contornada chamando a API direto. O valor é renderizado em `<a href={lesson.video_url}>`.

**Evidência** (`docs/evidencias/vulns/vuln-06-validacao-url.txt`, gerada por `ruby security/tools/url_validation_check.rb`):
```
javascript:alert(document.domain)             antigo=ACEITA  novo=rejeita
data:text/html,<script>alert(1)</script>      antigo=ACEITA  novo=rejeita
texto qualquer http://exemplo.com             antigo=ACEITA  novo=rejeita
https://youtube.com/watch?v=abc123            antigo=ACEITA  novo=ACEITA
```

**Por que Baixa.** O React 19 neutraliza URLs `javascript:` em `href`: confirmamos no código do `react-dom` 19.2, que troca o link por um que lança "React has blocked a javascript: URL". **Na interface atual o script não executa.** A falha continua real: o dado malicioso fica armazenado e qualquer outro cliente da API (app mobile, e-mail, versão futura do front) ficaria exposto. Classificamos como *latente*.

**Causa raiz.** Validação de URL feita com a ferramenta errada (regex de extração de URI, não de validação) e confiança na validação do frontend.

**Correção.** `URI.parse` + **allowlist de esquema** (`http`/`https`), host com domínio, sem `user:senha@`, máx. 2048 caracteres, normalização. Limites de tamanho em título, nome e descrição. O frontend só renderiza `<a href>` se o protocolo for http/https (defesa em profundidade).

**Verificação.** 11 testes novos (8 URLs maliciosas/inválidas, normalização, tamanho, rejeição via API) + PoC + regra Semgrep `unanchored-uri-regexp-validation`.

---

### VULN-07 — Dependências com vulnerabilidades conhecidas

| | |
|---|---|
| **Severidade** | **Média** (contexto) — CVSS 3.1 **7.4** (pior CVE alcançável: `jwt`, `AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N`) |
| **Categoria** | OWASP **A03:2025 Software Supply Chain Failures** · CWE-1395 |
| **Onde** | `backend/Gemfile.lock`, `frontend/package-lock.json` |
| **Correção** | commit `8ca68c5` |

**Descrição.** bundler-audit: **30 avisos** em 14 gems. npm audit: **14** (11 altas). Destaques e **análise de explorabilidade**:

| Dependência | CVE | Gravidade | Explorável aqui? |
|---|---|---|---|
| activestorage 8.1.3 | CVE-2026-66066 | Crítica | **Não diretamente:** exige upload de imagens + libvips. O app não usa uploads e a imagem não tinha libvips, mas as rotas públicas do Active Storage estavam montadas |
| jwt 2.10.2 | CVE-2026-45363 (bypass de HMAC com chave vazia) | Alta | **Não:** a chave nunca é vazia (o Rails recusa subir sem `secret_key_base`). Mas é a biblioteca que protege a autenticação |
| puma 8.0.1 | CVE-2026-47736/47737 | Alta | Não: exige PROXY protocol, desligado |
| vite 8.0.x | GHSA-9jrq-w75r-8gcw, GHSA-rq7h-c2jc-7f22, … | Alta | **Sim, enquanto o dev server estava exposto** (VULN-05) |
| nokogiri, net-imap, loofah, rails-html-sanitizer, websocket-driver, … | várias | Baixa–Média | Majoritariamente em componentes não usados |

**Impacto.** Software com falhas públicas, que podem virar exploráveis com uma mudança pequena no código (ex.: adicionar upload de avatar ativaria a CVE-2026-66066). Sem verificação automática, o problema volta a cada nova CVE.

**Causa raiz.** Ausência de processo de atualização e de verificação de dependências (o `ci.yml` do projeto estava em `backend/.github/` e nunca rodava).

**Correção.** Atualização patch-level (rails 8.1.4, jwt 2.10.3, puma 8.0.2, nokogiri 1.19.4…) → **0 vulnerabilidades** em ambos. Remoção de gems e frameworks não usados (kamal, thruster, image_processing/libvips, solid_queue, solid_cable, Active Storage etc.). **Processo:** bundler-audit, npm audit e Trivy no CI a cada push e toda semana; Dependabot com *cooldown* de 7 dias; imagens escaneadas antes do deploy (gate) e com SBOM assinado.

---

### VULN-08 — Tempo de resposta do login revela e-mails cadastrados

| | |
|---|---|
| **Severidade** | **Baixa** (contexto) — CVSS 3.1 **5.3** `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N` |
| **Categoria** | OWASP **A07:2025** · CWE-208 (discrepância de tempo), CWE-204 |
| **Onde** | `AuthenticationController#login` |
| **Correção** | commit `01da412` |

**Descrição.** `User.find_by_email(...)&.authenticate(...)` só calcula o bcrypt (≈250 ms com custo 12) quando o e-mail existe. E-mail inexistente responde em poucos ms. Mesmo com a mensagem genérica, o **tempo** revela quem tem conta.

**Reprodução.** `python security/poc/poc.py --only VULN-08` compara a mediana de tempo entre um e-mail existente e um inexistente. A versão original mostra diferença de centenas de ms; a corrigida, nenhuma diferença relevante.

**Impacto.** Lista de e-mails cadastrados para phishing direcionado e para focar ataques de senha (VULN-03).

**Causa raiz / correção.** Atalho de execução dependente de dado secreto. Trocado por `User.authenticate_by` (Rails 7.1+), que calcula um hash mesmo quando o usuário não existe. E-mails passam a ser normalizados (`strip` + `downcase`).

**Risco residual (documentado).** O cadastro ainda informa "e-mail já usado". Escondê-lo exige confirmação por e-mail (recomendação R8). Hoje é mitigado pelo rate limit de cadastro.

---

### VULN-09 — Política de senha fraca

| | |
|---|---|
| **Severidade** | **Média** — CVSS 3.1 **4.8** `AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N` |
| **Categoria** | OWASP **A07:2025** · CWE-521 |
| **Onde** | `User` (`validates :password, length: { minimum: 6 }`) |
| **Correção** | commit `c24a90e` |

**Descrição / reprodução.** `POST /signup` com senha `123456` → **201** na versão original (corrigido: 422).

**Correção (NIST SP 800-63B).** Mínimo de **12** caracteres; lista de senhas comuns; recusa de senhas com 1–2 caracteres distintos e de senhas que contêm o próprio e-mail. **Sem** regras de composição forçada ("1 maiúscula, 1 símbolo"), que levam a senhas previsíveis. Frases-senha longas são aceitas. Atualizar outros campos do perfil não exige reenviar a senha.

---

## 5. Controles testados que estavam corretos

Também é resultado de um pentest saber o que **não** está vulnerável:

| Teste | Resultado |
|---|---|
| Usuário B editar/excluir curso de A (`PUT/DELETE /courses/:id`) | **Protegido** — 403 (testes existentes + PoC `CONTROLE`) |
| Usuário B criar/editar/excluir aula no curso de A | Protegido — 403 |
| Mass assignment (`course[creator_id]`, `lesson[course_id]`) | Protegido — strong params não permitem esses campos |
| SQL injection | Não encontrado — só ActiveRecord parametrizado, nenhum SQL concatenado |
| JWT `alg: none` na versão original | Não explorável — a gem `jwt` 2.x usa `HS256` por padrão. Agora o algoritmo é explícito |
| CSRF | **Não se aplica**: a API não usa cookies. O token vai no header `Authorization`, que um site de terceiros não consegue enviar. Se a sessão migrar para cookie (R6), será obrigatório `SameSite=Strict` + token CSRF |
| CORS | Restrito a uma origem (agora configurável e, atrás do LB, desnecessário: mesma origem) |
| Segredos no histórico Git | Nenhum (Gitleaks) |

---

## 6. Hardening implementado (além das correções)

| # | Melhoria | Onde |
|---|---|---|
| H1 | **Rate limiting em 3 camadas** (borda + IP + conta) com store compartilhado entre réplicas | Nginx, Traefik, `RateLimiting`, `User#register_failed_login!` |
| H2 | **Cabeçalhos de segurança**: CSP sem `unsafe-inline`/`unsafe-eval`, HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, COOP; API com `CSP default-src 'none'`, `CORP` e `Cache-Control: no-store` | `frontend/nginx/security-headers.conf`, `config/application.rb` |
| H3 | **Validação consistente no backend**: allowlist de URL, limites de tamanho, normalização de e-mail/título | modelos |
| H4 | **JWT endurecido**: algoritmo fixo, claims obrigatórias, `jti` + revogação, chave derivada, TTL configurável | `JsonWebToken`, `RevokedToken` |
| H5 | **Senhas**: bcrypt (já existia) + política NIST + bloqueio de senhas comuns | `User` |
| H6 | **Redução de superfície**: só ActiveRecord + ActionController carregados; 5 gems removidas | `config/application.rb`, `Gemfile` |
| H7 | **Containers**: non-root, rootfs read-only, `cap_drop: ALL`, `no-new-privileges`, limites de CPU/memória/pids, redes segmentadas (`data` interna), portas só em 127.0.0.1 | `docker-compose.yml`, Dockerfiles |
| H8 | **Banco com menor privilégio**: a API usa o usuário `coursesphere`, sem superusuário | `deploy/compose/postgres/initdb` |
| H9 | **Kubernetes**: Pod Security `restricted`, NetworkPolicies default-deny, Kyverno (limites, sem `:latest`, registries permitidos, rootfs read-only, probes obrigatórias), sem token de service account | `deploy/k8s`, `deploy/policies` |
| H10 | **Cadeia de suprimentos**: Actions fixadas por SHA, ferramentas com SHA-256, Dependabot com cooldown, SBOM, imagens assinadas (cosign), gate de CVE antes do deploy | `.github/` |
| H11 | **Detecção**: eventos de segurança em log JSON + métricas + alertas (força bruta, contas bloqueadas, pico de 403) | `lib/observability`, regras Prometheus |

---

## 7. Recomendações priorizadas

**Ordem usada nas correções** (o que corrigir primeiro e por quê):

| Prioridade | Itens | Motivo |
|---|---|---|
| **P1 — imediato** | VULN-04, VULN-05, VULN-03, VULN-07 | Exploráveis **sem conta**, com esforço trivial (senha pública, páginas de debug abertas, tentativas ilimitadas) ou com correção barata e de alto ganho (atualizar dependências) |
| **P2 — curto prazo** | VULN-01, VULN-02, VULN-09 | Exigem uma conta (o cadastro é aberto, então a barreira é baixa) e afetam confidencialidade e sessões |
| **P3 — planejado** | VULN-06, VULN-08 | Já mitigadas por outro controle (React 19, rate limit) ou de baixo impacto |

**Próximas recomendações (não implementadas):**

| ID | Recomendação | Prioridade |
|---|---|---|
| R1 | Banco gerenciado com alta disponibilidade, backups automáticos e PITR (ex.: RDS Multi-AZ) | Alta |
| R2 | TLS de ponta a ponta (cert-manager + Let's Encrypt) e `FORCE_SSL=true` | Alta |
| R3 | Gestão de segredos com cofre (AWS Secrets Manager/Vault + External Secrets Operator) e rotação | Alta |
| R4 | MFA (TOTP/WebAuthn), ao menos para instrutores | Média |
| R5 | Paginação no servidor em `GET /courses` (hoje devolve tudo: risco de desempenho e de disponibilidade) | Média |
| R6 | Sessão em cookie `HttpOnly; Secure; SameSite=Strict` + proteção CSRF, em vez de `localStorage` | Média |
| R7 | Testes de carga (k6) para validar SLOs e dimensionar HPA/pool do banco | Média |
| R8 | Confirmação de e-mail no cadastro (elimina a enumeração residual da VULN-08) | Baixa |
| R9 | DAST autenticado (ZAP com contexto de login) e pentest periódico | Baixa |

---

## 8. Confiabilidade (SRE)

### 8.1 Arquitetura

```mermaid
flowchart LR
  U[Usuário / navegador] -->|HTTP :8080| LB[Nginx LB<br/>rate limit, headers, retry]
  LB -->|/| FE[frontend<br/>nginx estático]
  LB -->|/api/* round-robin| A1[api-1 Puma/Rails]
  LB -->|/api/*| A2[api-2 Puma/Rails]
  A1 & A2 -->|rede interna 'data'| DB[(PostgreSQL)]
  P[Prometheus] -->|/metrics com token| A1 & A2
  P --> AM[Alertmanager]
  G[Grafana] --> P
  U -. randomuser.me .-> EXT[(API externa)]
```

No Kubernetes, a mesma topologia usa Traefik (ingress), Service + Deployment com 2–5 réplicas (HPA), PDB, StatefulSet do PostgreSQL, kube-prometheus-stack e Loki/Alloy para logs. Tudo é sincronizado pelo ArgoCD (seção 9).

### 8.2 SLIs e SLOs

| | SLI (o que medimos) | SLO (meta, janela de 30 dias) | Por que importa |
|---|---|---|---|
| **SLO-1** | Disponibilidade do CRUD: fração de requisições a `/courses*` e `/lessons*` **sem erro 5xx** | **99,5%** (orçamento: 0,5% ≈ 3h36min/mês) | É a função principal do produto |
| **SLO-2** | Latência do login: fração de `POST /login` em **menos de 500 ms** | **99%** | O login é a porta de entrada. O bcrypt (≈250 ms) já consome metade do orçamento |
| **SLO-3** | Latência de leitura do CRUD: fração de `GET` de cursos/aulas em **menos de 250 ms** | **99%** | Experiência de navegação |

Medição, consultas PromQL e alertas: [`docs/observabilidade.md`](observabilidade.md). Os alertas usam **burn rate multi-janela** (Google SRE Workbook): avisam quando o orçamento de erro está sendo consumido rápido demais, e não a cada erro isolado.

### 8.3 Observabilidade implementada

- **Logs estruturados (JSON):** uma linha por requisição (método, rota, status, duração, `request_id`, `user_id`, IP real, réplica), eventos de segurança e erros. O `request_id` gerado pelo Nginx aparece no log do balanceador **e** no da API, o que permite seguir uma requisição de ponta a ponta. E-mails nunca em claro (hash).
- **Métricas Prometheus** (`/metrics`, protegido por token): requisições por rota/status, histograma de latência, requisições em andamento, eventos de segurança, pool de conexões do banco, uptime/versão por réplica.
- **Health checks:** `/health/live` (processo vivo, sem tocar no banco: o orquestrador não reinicia a API por causa do banco) e `/health/ready` (testa o PostgreSQL: réplica sem banco sai do balanceador).
- **Dashboard Grafana provisionado** ("CourseSphere — SLOs, tráfego e segurança"): SLO e orçamento de erro restante, réplicas no ar, requisições/s **por réplica** (prova visual do balanceamento), status, erros, latência p50/p95/p99, pool do banco, eventos de segurança e 401/403/429.
- **Alertas** (Alertmanager) com runbooks em [`docs/runbooks/`](runbooks/).

### 8.4 Principais riscos de disponibilidade

| # | Risco | Impacto | Situação |
|---|---|---|---|
| D1 | **PostgreSQL único** (SPOF) | Indisponibilidade total se o banco cair. Perda de dados sem backup | **Aberto** no lab. Readiness tira as réplicas do LB e os timeouts curtos evitam travamento em cascata. Recomendação R1 |
| D2 | Instância única da API (original) | Qualquer falha/deploy = indisponibilidade | **Resolvido**: 2+ réplicas, rolling update com `maxUnavailable: 0`, PDB, spread entre nós |
| D3 | Migração no start de cada container (original) | Réplicas migrando em paralelo; deploy quebrado derruba todas | **Resolvido**: passo único (`migrate` / hook do ArgoCD) antes das réplicas |
| D4 | Estado local por réplica (rate limit em memória, segredo JWT gerado por instância em dev) | Comportamento inconsistente atrás do LB (limites dobrados, tokens recusados) | **Resolvido**: estado compartilhado no PostgreSQL e segredo único via variável de ambiente |
| D5 | `GET /courses` sem paginação | Latência e memória crescem com a base; risco de esgotar o pool | **Aberto** — recomendação R5 |
| D6 | Login usa CPU de propósito (bcrypt) | Inundação de logins satura a CPU e afeta todo o resto | **Mitigado** por rate limit na borda e na app, HPA por CPU e alerta |
| D7 | Pool de conexões x threads | Threads esperando conexão → latência | Pool = threads (5); métrica `db_pool{state="waiting"}` + alerta |
| D8 | Dependência externa (randomuser.me) | Card do "instrutor convidado" não carrega | Isolado: chamada direta do navegador, falha só afeta o card |
| D9 | Sem backup/restore testado | Perda de dados | **Aberto** — R1 (backup automatizado + teste de restore) |

### 8.5 Recomendações de resiliência

1. **Banco gerenciado Multi-AZ** com failover automático, backups diários e PITR, e **teste de restore** trimestral (D1, D9).
2. **PgBouncer** entre API e banco quando escalar réplicas (evita estourar `max_connections`).
3. **Timeouts e retries** já existem (conexão 3 s, statement 5 s, proxy 2 s/15 s, retry só em métodos idempotentes). Próximo passo: **circuit breaker** para dependências externas, se a API passar a chamá-las.
4. **Paginação** e índices conforme a base crescer (D5). Testes de carga para calibrar HPA e SLOs (R7).
5. **Multi-AZ** para os nós do cluster e `topologySpreadConstraints` por zona (hoje, por nó).
6. **Chaos testing** simples (matar uma réplica e o banco em homologação) para validar alertas e runbooks.

### 8.6 Escalabilidade e balanceamento — evidência

- **Docker compose:** Nginx com `upstream` round-robin para `api-1` e `api-2`, health check passivo (`max_fails=3 fail_timeout=10s`) e retry na outra réplica para métodos idempotentes. `python scripts/lb_demo.py` faz 20 requisições e mostra a distribuição pelo header `X-Served-By`. O log JSON do Nginx registra o `upstream` de cada requisição, e o dashboard mostra requisições/s por réplica. O workflow **E2E** salva essas três evidências (`lb-demo.txt`, `lb-access-log.txt`, `prometheus-requests-por-instancia.json`).
- **Kubernetes:** Service balanceando 2–5 pods (HPA por CPU), Traefik na frente, réplicas espalhadas entre nós.

---

## 9. Infraestrutura, GitOps e pipeline

| Pilar | Implementação |
|---|---|
| **Infraestrutura** | Terraform cria um cluster **kind** (1 control-plane + 2 workers), namespaces com Pod Security e segredos aleatórios (fora do Git), e instala o **ArgoCD** (`deploy/terraform/kind`) |
| **GitOps** | Padrão **app-of-apps**: o Terraform cria só a Application `root`. O ArgoCD aplica, em ordem (*sync waves*), Traefik, metrics-server, Kyverno, kube-prometheus-stack, Loki, Alloy, políticas, observabilidade e a aplicação, com `prune` + `selfHeal` |
| **Automação (CI/CD)** | `ci.yml` (testes, lint, build, validação de toda a IaC), `security.yml` (SAST/SCA/segredos/IaC, semanal também), `cd.yml` (build → scan → SBOM → push → assinatura → commit da nova tag = deploy), `e2e.yml` (compose + PoCs + ZAP), `k8s-e2e.yml` (Terraform + ArgoCD num runner limpo) |
| **Observabilidade** | Logs JSON, Prometheus, Alertmanager, Grafana, Loki/Alloy, SLOs, runbooks |
| **Segurança** | Semgrep (regras próprias), Brakeman, bundler-audit, npm audit, Trivy (fs, config, imagem), Gitleaks, ZAP, Kyverno, Pod Security, NetworkPolicies, cosign |

Toda a configuração do Kubernetes/ArgoCD foi validada sem cluster: **todos os 9 Applications** renderizados com os valores reais e validados com kubeconform (`scripts/validate_gitops.py`); Terraform com `terraform validate`; regras com `promtool`; políticas Kyverno contra o schema real da CRD.

---

## 10. Limitações e transparência

- A análise estática, as ferramentas de SAST/SCA/IaC e a validação de toda a infraestrutura foram executadas durante o trabalho (saídas em `docs/evidencias/`).
- As **evidências dinâmicas** (PoC contra as versões original e corrigida, distribuição do balanceador, métricas por réplica, ZAP, cluster kind + ArgoCD) são geradas pelos workflows `E2E` e `K8s E2E` do GitHub Actions e publicadas como artefatos de cada execução. Também podem ser reproduzidas localmente com os comandos do README.
- O DAST (ZAP baseline) é passivo e não autenticado. Testes de carga não foram executados (R7, R9).
- O PostgreSQL do laboratório é de instância única, de propósito (risco D1 documentado).

---

## Anexo A — Evidências

| Arquivo | Conteúdo |
|---|---|
| `docs/evidencias/baseline/` | Brakeman, Semgrep, bundler-audit e npm audit da versão original |
| `docs/evidencias/depois/` | bundler-audit, npm audit e regras Semgrep próprias (original × corrigida) |
| `docs/evidencias/vulns/vuln-06-validacao-url.txt` | Regex antiga × validação nova |
| Artefato CI `evidencias-versao-original` | PoC contra a v0-original (esperado: VULNERÁVEL) |
| Artefato CI `evidencias-versao-corrigida` | PoC (CORRIGIDO), balanceamento, logs JSON, métricas, headers |
| Artefato CI `zap-baseline` | Relatório OWASP ZAP |
| Artefato CI `evidencias-kubernetes` | Applications do ArgoCD, pods, políticas, PoC via ingress |

## Anexo B — Mapa de correções

| Achado | Commit | Testes automatizados |
|---|---|---|
| VULN-01 | `cb35745` | `lessons_controller_test.rb` (6 novos) |
| VULN-02 | `076e105` | `authentication_controller_test.rb` (7 novos) |
| VULN-03 | `416b854` | `brute_force_protection_test.rb` (6) |
| VULN-04 | `ebdd6e8` | seeds no CI + Semgrep |
| VULN-05 | `386a1ce`, `8efbacd` | PoC + Semgrep + Trivy |
| VULN-06 | `72b5674` | `lesson_test.rb` (10 novos), `lessons_controller_test.rb` (1) |
| VULN-07 | `8ca68c5` | bundler-audit / npm audit / Trivy no CI |
| VULN-08 | `01da412` | `authentication_controller_test.rb` (2 novos) |
| VULN-09 | `c24a90e` | `user_test.rb` (6 novos), `authentication_controller_test.rb` (1) |
