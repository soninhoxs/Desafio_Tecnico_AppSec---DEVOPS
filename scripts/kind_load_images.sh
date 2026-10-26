#!/usr/bin/env bash
# Constrói as imagens localmente e carrega nos nós do cluster kind, para usar
# o overlay "kind-local" (sem registry). Só precisa de Docker.
#
#   ./scripts/kind_load_images.sh [nome-do-cluster]
set -euo pipefail

CLUSTER="${1:-coursesphere}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

docker build -t coursesphere-api:local "$ROOT/backend"
docker build -t coursesphere-frontend:local "$ROOT/frontend"

nodes=$(docker ps --filter "label=io.x-k8s.kind.cluster=${CLUSTER}" --format '{{.Names}}')
if [ -z "$nodes" ]; then
  echo "Nenhum nó do cluster kind '${CLUSTER}' encontrado. Rode o terraform apply antes." >&2
  exit 1
fi

for image in coursesphere-api:local coursesphere-frontend:local; do
  for node in $nodes; do
    echo "-> ${image} em ${node}"
    docker save "$image" | docker exec -i "$node" ctr --namespace=k8s.io images import --all-platforms -
  done
done
echo "Imagens carregadas. Use app_overlay=\"kind-local\" no Terraform."
