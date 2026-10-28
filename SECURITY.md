# Política de segurança

## Versões suportadas

| Versão | Recebe correções de segurança |
|---|---|
| `main` (versão corrigida) | ✅ |
| tag `v0-original` (versão analisada, vulnerável de propósito) | ❌ — mantida só como evidência do pentest |

## Como reportar uma vulnerabilidade

**Não abra issue pública** com detalhes de uma falha de segurança.

Use o canal privado do GitHub: aba **Security → Report a vulnerability**
(<https://github.com/soninhoxs/Desafio_Tecnico_AppSec---DEVOPS/security/advisories/new>).
O relato fica visível só para quem mantém o repositório até a correção ser publicada.

Inclua, se possível:

- componente afetado (API, frontend, Nginx, manifests Kubernetes, pipeline) e versão/commit;
- passos para reproduzir (requisições `curl` ou script), resultado esperado e obtido;
- impacto que você enxerga e, se tiver, sugestão de correção.

## Prazos

| Etapa | Prazo |
|---|---|
| Confirmação de recebimento | até 3 dias úteis |
| Avaliação inicial e severidade (CVSS 3.1) | até 7 dias |
| Correção | Crítica: 7 dias · Alta: 30 dias · Média: 90 dias · Baixa: próxima versão |

Depois da correção, o achado é registrado no relatório ([`docs/RELATORIO.md`](docs/RELATORIO.md)) com causa raiz,
correção e teste automatizado, e ganha uma regra de regressão quando fizer sentido
(Semgrep em [`security/semgrep/`](security/semgrep/) ou teste em `backend/test/`).

## Escopo e regras para testes

- **Teste só em ambiente próprio**: suba o laboratório isolado com `docker compose up` (veja o [README](README.md)).
  Não teste contra instâncias de terceiros.
- Não faça negação de serviço volumétrica, engenharia social nem acesso a dados de outras pessoas.
- Pesquisa feita de boa-fé, dentro destas regras, é bem-vinda e não será tratada como ataque.

## Controles de segurança do projeto

O que roda automaticamente (detalhes no README e em [`docs/VERIFICACAO.md`](docs/VERIFICACAO.md)):

- **A cada push/PR:** Semgrep (regras próprias bloqueiam regressões), Brakeman, bundler-audit, npm audit,
  Trivy (dependências, segredos e IaC) e Gitleaks no histórico completo.
- **Antes de cada deploy:** Trivy na imagem final (HIGH/CRITICAL com correção bloqueiam), SBOM CycloneDX e
  assinatura das imagens com cosign.
- **Atualizações:** Dependabot semanal, com espera de 7 dias para versões recém-publicadas.
- **Modelagem de ameaças:** [`docs/threat-model.md`](docs/threat-model.md) (STRIDE).
