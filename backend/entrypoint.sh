#!/bin/bash
set -euo pipefail

# /rails/tmp é tmpfs vazio no compose (rootfs read-only). O diretório criado
# no build fica escondido pelo volume, e `rm -f` de um caminho cujo pai não
# existe sai com status 1 — com `set -e` o container morre antes do Puma.
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
