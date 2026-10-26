# Runbook — Possível força bruta (`PossibleBruteForce` / `AccountsBeingLocked` / `AccessDeniedSpike`)

## Diagnóstico
1. Grafana → "Eventos de segurança por tipo": `login_failure`, `account_locked`, `rate_limited`, `access_denied`.
2. De onde vem? Eventos têm `remote_ip`, `email_fp` (hash do e-mail) e `user_id`:
   - compose: `docker compose logs api-1 api-2 | grep 'security.login_failure'`
   - Loki: `sum by (remote_ip) (count_over_time({app="coursesphere-api"} | json | event="security.login_failure" [15m]))`
3. Padrão:
   - **Muitas falhas, poucos IPs** → força bruta clássica (rate limit por IP já atua).
   - **Muitos IPs, muitas contas** → credential stuffing distribuído (bloqueio por conta atua; considerar CAPTCHA/WAF).
   - **`access_denied` em alta** → alguém testando IDs de cursos/aulas de outros usuários (tentativa de IDOR).

## Mitigação
- Bloquear IPs/faixas ofensivas na borda (Nginx `deny` / middleware `ipAllowList` do Traefik / WAF).
- Contas com sucesso de login suspeito logo após muitas falhas → forçar troca de senha e revogar tokens (`RevokedToken`).
- Avaliar MFA para as contas atacadas (recomendação R4).
