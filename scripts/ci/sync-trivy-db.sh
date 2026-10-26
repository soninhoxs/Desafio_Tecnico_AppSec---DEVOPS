#!/usr/bin/env bash
# Publica o banco de vulnerabilidades do Trivy no GHCR do projeto.
#
# O artefato oficial tem ~130 MiB (mirror.gcr.io/aquasec/trivy-db:2). Baixá-lo
# dentro do gate, em cada imagem, deixa o deploy pesado e acoplado a um mirror
# público. Aqui a cópia mora no mesmo registry das imagens da aplicação. O
# runner reutiliza o cache; este script só transfere bytes quando o digest muda.
#
# Exige `oras` autenticado no GHCR (docker login / oras login).
# Se o mirror público cair e a cópia já existir, o deploy segue com ela.
set -euo pipefail

SRC="${TRIVY_DB_UPSTREAM:-mirror.gcr.io/aquasec/trivy-db:2}"

if [[ -z "${TRIVY_DB_IMAGE:-}" ]]; then
  if [[ -z "${GITHUB_REPOSITORY_OWNER:-}" ]]; then
    echo "defina TRIVY_DB_IMAGE (ex.: ghcr.io/org/coursesphere-trivy-db:2)" >&2
    exit 1
  fi
  owner="${GITHUB_REPOSITORY_OWNER,,}"
  TRIVY_DB_IMAGE="ghcr.io/${owner}/coursesphere-trivy-db:2"
fi

fetch_digest() {
  local ref="$1" out
  if ! out="$(oras manifest fetch --descriptor "$ref" 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])'
}

src_digest="$(fetch_digest "$SRC" || true)"
dest_digest="$(fetch_digest "$TRIVY_DB_IMAGE" || true)"

if [[ -n "$src_digest" && "$src_digest" == "$dest_digest" ]]; then
  echo "banco já está em ${TRIVY_DB_IMAGE} (${src_digest})"
  exit 0
fi

if [[ -n "$src_digest" ]]; then
  echo "publicando ${SRC} -> ${TRIVY_DB_IMAGE}"
  oras copy "$SRC" "$TRIVY_DB_IMAGE"
  exit 0
fi

if [[ -n "$dest_digest" ]]; then
  echo "mirror público indisponível; o deploy usa a cópia já publicada em ${TRIVY_DB_IMAGE} (${dest_digest})" >&2
  exit 0
fi

echo "não consegui ler ${SRC} nem ${TRIVY_DB_IMAGE}" >&2
oras manifest fetch --descriptor "$SRC" >&2 || true
exit 1
