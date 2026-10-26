# Verificação — como provar que a entrega funciona

Este documento é o roteiro para repetir, na ordem, tudo o que o GitHub Actions cobra. Serve para quem vai corrigir uma falha de CI e para quem vai avaliar o repositório sem abrir os workflows.

O relatório de segurança (achados, severidade, causa raiz) continua em [`RELATORIO.md`](RELATORIO.md). Aqui está só a **prova**: o que rodar, o que tem que passar e o que uma falha significa.

## 1. O que cada suíte prova

| Suíte | Prova | Onde |
|---|---|---|
| Schema | As migrations e o `db/schema.rb` descrevem o mesmo banco. Um clone novo sobe igual ao de quem desenvolveu. | `ci.yml` → job Backend testes |
| Minitest | Autorização, logout, força bruta, senha, URL de vídeo e health/métricas. | `backend/test/` |
| RuboCop | O Ruby segue o estilo do projeto. Não é teste de segurança. | `backend/.rubocop.yml` |
| ESLint + build | O frontend compila e o lint de segurança/React passa. | `frontend/` |
| IaC | Terraform, charts do ArgoCD, regras Prometheus e o compose são válidos **sem** subir cluster. | `scripts/validate_gitops.py` |
| SAST/SCA | Semgrep, Brakeman, bundler-audit, npm audit, Trivy no código, Gitleaks. | `security.yml` |
| E2E corrigido | O compose sobe, as duas réplicas recebem tráfego, os PoCs saem `CORRIGIDO` e o ZAP roda. | `e2e.yml` job `fixed` |
| E2E original | Na tag `v0-original` os mesmos PoCs saem `VULNERÁVEL`. É a evidência de que o achado existia. | `e2e.yml` job `original` |
| CD | A imagem final (não o código-fonte) não tem CVE HIGH/CRITICAL com correção disponível. | `cd.yml` |
| K8s E2E | Terraform + ArgoCD sobem o cluster e o PoC passa pelo ingress. Manual e semanal. | `k8s-e2e.yml` |

## 2. Pré-requisitos

| Modo | Precisa de |
|---|---|
| Testes da API | Ruby **4.0.9** (`.ruby-version`), Bundler, PostgreSQL **18** compatível com `postgres:18.6` |
| Frontend | Node 24 (o CI usa a versão do `frontend/`) |
| Compose / E2E | Docker com Compose v2 e Python 3.9+ (só biblioteca padrão) |
| IaC | Python 3, Helm, Terraform ≥ 1.9, e as ferramentas que `scripts/ci/install-tools.sh` baixa (kubeconform, promtool) |

Não use a senha de demonstração de um `.env` antigo depois de `docker compose down -v`. O volume novo exige o mesmo `.env`, ou um `.env` novo gerado de novo.

## 3. API — schema, testes e seeds

O job de CI quebrou quando `db/schema.rb` divergia do que o Rails grava depois de migrar um banco vazio. O dumper **ordena índices em ordem alfabética da linha**. A tabela `solid_cache_entries` tinha o índice de `key_hash` antes do índice composto; o dump faz o contrário. Qualquer edição manual de `schema.rb` que mude ordem, aspas ou `precision` faz o job falhar em segundos, antes dos testes.

Com PostgreSQL no ar (usuário `postgres`, senha `postgres`, host `localhost`):

```bash
cd backend
bundle install
export RAILS_ENV=test CI=true DB_HOST=localhost DB_USER=postgres DB_PASSWORD=postgres
bin/rails db:create db:migrate
bin/rails db:schema:dump
git diff --exit-code db/schema.rb
bin/rails db:test:prepare test
bin/rails db:seed
bin/rubocop
```

Saída esperada do schema: `git diff` não imprime nada e o comando termina com status 0.

Saída esperada dos testes: todos os arquivos em `backend/test/` verdes, inclusive

- `courses_controller_test.rb` — outro usuário não altera nem apaga curso alheio
- `lessons_controller_test.rb` — rascunho só aparece para o criador (VULN-01)
- `authentication_controller_test.rb` — logout invalida o JWT (VULN-02) e o login não denuncia se o e-mail existe (VULN-08)
- `brute_force_protection_test.rb` — bloqueio depois de tentativas (VULN-03)
- `user_test.rb` e o signup — senha curta ou comum é rejeitada (VULN-09)
- `lesson_test.rb` — `javascript:` é rejeitado (VULN-06)

O seed no ambiente de teste **não** usa senha padrão. Sem `DEMO_USER_PASSWORD`, ele gera uma senha aleatória e imprime no log. Em produção o seed só roda com `ALLOW_DEMO_SEED=true`.

Se o `git diff` de `schema.rb` falhar de novo: não reordene o arquivo à mão. Rode o dump acima e commit o resultado. O cabeçalho do arquivo diz para não editá-lo; o CI existe para garantir isso.

## 4. Frontend

```bash
cd frontend
npm ci
npm run lint
npm run build
```

O build de produção não sobe o Vite. A imagem final é Nginx com os arquivos de `dist/`.

## 5. Ambiente completo (o que o E2E faz)

```bash
python scripts/bootstrap_env.py
docker compose up -d --build
python scripts/wait_for_http.py http://localhost:8080/api/health --timeout 480
python scripts/lb_demo.py -n 20
python security/poc/poc.py --base-url http://localhost:8080/api --expect fixed
```

O que tem que aparecer:

1. `wait_for_http` termina com HTTP 200 em `/api/health`.
2. `lb_demo.py` mostra `x-served-by=api-1` **e** `api-2`. Se só uma réplica aparecer, o balanceador ou o health da outra réplica falhou.
3. O PoC imprime `CORRIGIDO` ou `PROTEGIDO` em todos os casos. Qualquer `VULNERÁVEL` é falha.

Health checks do compose usam **curl**, não wget. A imagem `nginxinc/nginx-unprivileged` instala curl e não garante wget. Um `HEALTHCHECK` com wget marca o container como unhealthy; o Compose espera `service_healthy` no frontend antes de subir o balanceador e o `up` termina com erro. Foi isso que derrubou o job E2E da versão corrigida.

Para a versão original (tem que continuar vulnerável):

```bash
git worktree add ../coursesphere-original v0-original
cd ../coursesphere-original && docker compose up -d --build
python scripts/wait_for_http.py http://localhost:3000/courses --status 401 --timeout 600
python security/poc/poc.py --base-url http://localhost:3000
```

Aqui o esperado é `VULNERÁVEL` nos achados documentados. O compose dessa tag publica a API na porta 3000, sem o prefixo `/api`.

## 6. Imagens e o gate do CD

`security.yml` examina o **repositório** (`trivy fs`, `trivy config`). `cd.yml` examina a **imagem construída**:

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 <imagem>
```

`--ignore-unfixed` só ignora CVE sem correção publicada. HIGH/CRITICAL **com** versão corrigida reprovam o job, mesmo que o `npm audit` e o `bundler-audit` estejam limpos — o CVE está no Alpine ou no Debian da imagem base, não no `package-lock` nem no `Gemfile.lock`.

Por isso os Dockerfiles atualizam os pacotes do sistema no build (`apk upgrade` no frontend, `apt-get upgrade` na API), mantendo a tag da imagem base fixa. A tag pinada evita um salto silencioso de Nginx ou de Ruby; o upgrade pega o patch de segurança que saiu depois dessa tag.

Conferir localmente, com Docker e Trivy:

```bash
docker build -t coursesphere-frontend:local frontend
docker build -t coursesphere-api:local backend
trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 coursesphere-frontend:local
trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 coursesphere-api:local
```

Status 0 nos dois comandos é o mesmo critério do CD.

## 7. Como ler uma falha no GitHub Actions

| Job vermelho | Onde olhar | Causa típica |
|---|---|---|
| Backend — testes, passo "Migrations geram exatamente o schema" | o `git diff` no log | `schema.rb` foi editado ou uma migration nova não foi dumpada. Rode a seção 3. |
| Backend — testes, passo dos testes | nome do teste | regressão de autorização, senha ou JWT. O teste cita o ID (VULN-0N). |
| Frontend — lint e build | ESLint | regra de React ou de segurança no `frontend/src`. |
| E2E versão corrigida, "Sobe o ambiente" | `docker compose logs` (o workflow imprime as últimas 200 linhas) | healthcheck, migration ou seed. Frontend unhealthy quase sempre é probe com binário que a imagem não tem. API unhealthy: `/health/ready` não fala com o PostgreSQL. |
| E2E versão corrigida, PoC | a linha `VULNERÁVEL` | a correção regrediu. O ID no PoC aponta o achado no relatório. |
| E2E versão original | um caso `CORRIGIDO` quando o esperado era falha | a tag `v0-original` foi movida, ou o PoC mudou e não distingue mais as duas versões. |
| CD, gate do Trivy | a tabela HIGH/CRITICAL | pacote do SO na imagem. Atualize o `apk`/`apt` do Dockerfile ou a tag da base se o patch ainda não entrou no repositório da distro. |
| Security | a ferramenta no nome do step | Semgrep próprio bloqueia; o restante é informativo ou gate, conforme `security.yml`. |

O workflow E2E da versão original e o da versão corrigida são independentes. Um verde e o outro vermelho é informativo: o original provar o achado não conserta o compose da `main`.

## 8. IaC sem cluster

```bash
python scripts/validate_gitops.py
```

Isso renderiza os charts do app-of-apps com os valores reais e passa kubeconform. Não substitui o `k8s-e2e.yml`, que sobe kind de verdade. Complementa o que o job "Infra" do `ci.yml` já faz: `terraform validate`, `promtool check rules` e `docker compose config`.

## 9. Ordem sugerida antes de abrir o pull request

1. Schema + Minitest + RuboCop (seção 3).
2. Lint e build do frontend (seção 4).
3. `python scripts/validate_gitops.py` se mexeu em `deploy/`.
4. Compose + PoC (seção 5) se mexeu em API, Nginx, Dockerfile ou seed.
5. Trivy nas duas imagens (seção 6) se mexeu em Dockerfile ou lockfile.

O CI repete 1, 2 e 3 em todo push. O E2E repete 4. O CD repete 6 na `main`.
