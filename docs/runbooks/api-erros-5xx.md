# Runbook — Erros 5xx no CRUD (`CrudErrorBudgetFastBurn` / `SlowBurn`)

**Impacto:** usuários recebendo erro ao listar/criar/editar cursos e aulas; orçamento de erro do SLO-1 (99,5%) sendo consumido.

## Diagnóstico
1. Grafana → "Taxa de erro 5xx do CRUD" e "Requisições/s por status": começou quando? Todas as réplicas ou uma só?
2. Logs de erro (têm `error_class` e `error_message`):
   - compose: `docker compose logs api-1 api-2 | grep '"level":"ERROR"'`
   - Loki: `{app="coursesphere-api"} | json | level="ERROR"`
3. Pegue um `request_id` do erro e busque no log do balanceador para ver a requisição completa.
4. Coincide com deploy? (ArgoCD / commits `deploy:`). Coincide com o banco (latência, `db_pool waiting`)?

## Mitigação
- Deploy recente → **rollback** (`git revert` do commit de deploy).
- Uma réplica com problema → removê-la (k8s: `kubectl delete pod <pod>`; o Deployment recria).
- Banco lento/indisponível → ver [latencia-alta](latencia-alta.md).
