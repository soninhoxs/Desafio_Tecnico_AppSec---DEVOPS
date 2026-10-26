#!/bin/bash
set -euo pipefail

# Remove PID de execuções anteriores (o container pode ter sido reiniciado).
rm -f tmp/pids/server.pid

# Migrações NÃO rodam mais em todo start de container:
# - com 2+ réplicas, todas tentariam migrar ao mesmo tempo;
# - db:prepare também roda os seeds quando o banco é criado.
# Elas rodam num passo único antes do deploy (serviço "migrate" no compose,
# Job de pre-sync no Kubernetes). RUN_DB_PREPARE=true mantém o comportamento
# antigo só para desenvolvimento local de uma instância.
if [ "${RUN_DB_PREPARE:-false}" = "true" ]; then
  echo "[entrypoint] RUN_DB_PREPARE=true -> bin/rails db:prepare"
  bin/rails db:prepare
fi

exec "$@"
