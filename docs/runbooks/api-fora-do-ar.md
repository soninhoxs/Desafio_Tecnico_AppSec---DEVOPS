# Runbook — API fora do ar (`ApiInstanceDown` / `ApiAllInstancesDown`)

**Impacto:** uma réplica fora = perda de redundância (o balanceador segue com as outras). Todas fora = CourseSphere indisponível.

## Diagnóstico
1. Quais réplicas caíram?
   - compose: `docker compose ps` (coluna STATUS/health)
   - k8s: `kubectl -n coursesphere get pods -l app.kubernetes.io/name=coursesphere-api`
2. Por quê?
   - compose: `docker compose logs --tail 200 api-1`
   - k8s: `kubectl -n coursesphere describe pod <pod>` (OOMKilled? CrashLoopBackOff? ImagePullBackOff?) e `kubectl logs <pod> --previous`
3. O banco está respondendo? `curl -s localhost:8080/api/health/ready` → `checks.database`. Se o banco caiu, siga o passo "Banco".
4. Foi deploy? ArgoCD → app `coursesphere` → histórico de sync. Compare com o último commit `deploy: sha-...`.

## Mitigação
- **Deploy ruim:** reverta o commit `deploy: sha-...` no Git (`git revert`) — o ArgoCD volta a versão anterior.
- **OOMKilled:** aumentar `limits.memory` no `deploy/k8s/base/api.yaml` (via PR) e investigar vazamento.
- **Banco:** ver logs do PostgreSQL (`docker compose logs db` / `kubectl logs coursesphere-db-0`), espaço em disco, conexões.

## Depois
Registrar o incidente (`docs/runbooks/postmortem-template.md`) e, se consumiu orçamento de erro, priorizar a correção.
