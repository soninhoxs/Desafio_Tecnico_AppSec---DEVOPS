#!/bin/bash
set -euo pipefail

# /rails/tmp é tmpfs vazio (rootfs read-only) e precisa ser gravável pelo
# uid 10001. O diretório do build fica escondido pelo volume. Sem permissão
# o mkdir falha, o container sai 1 e o compose não sobe a API.
mkdir -p tmp/pids tmp/cache tmp/sockets
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
