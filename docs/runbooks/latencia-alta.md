# Runbook — Latência alta (`LoginLatencySLOBurn` / `DatabaseConnectionPoolSaturated`)

## Diagnóstico
1. Grafana → "Latência por rota (p95)": só login ou tudo?
   - **Só login:** CPU saturada pelo bcrypt (inundação de logins?). Veja "Eventos de segurança" e o alerta `PossibleBruteForce`.
   - **Tudo:** banco ou saturação geral.
2. Pool do banco: painel "Requisições em andamento / pool do banco". `esperando conexão > 0` = pool esgotado.
3. CPU/memória: `kubectl top pods -n coursesphere` (k8s) / `docker stats` (compose).
4. Consultas lentas no PostgreSQL: `SELECT pid, now()-query_start AS duracao, query FROM pg_stat_activity WHERE state <> 'idle' ORDER BY 2 DESC;`

## Mitigação
- Ataque de login → os rate limits já devem responder 429; se não bastar, bloquear o IP/ASN na borda.
- Carga legítima → escalar réplicas (HPA faz automaticamente até 5; compose: adicionar `api-3`).
- Pool esgotado → revisar `RAILS_MAX_THREADS` x conexões do banco; considerar PgBouncer.
- `GET /courses` lento com base grande → paginação (recomendação R5 do relatório).
