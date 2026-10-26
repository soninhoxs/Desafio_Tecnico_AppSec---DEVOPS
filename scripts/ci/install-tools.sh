#!/usr/bin/env bash
# Instala ferramentas de segurança/validação no runner do CI com VERSÃO FIXA e
# verificação de SHA-256. Nada de "curl | sh" nem tag mutável: se o arquivo
# publicado mudar (release comprometido), o checksum falha e o job para.
#
#   scripts/ci/install-tools.sh trivy gitleaks kustomize kubeconform
set -euo pipefail

DEST="${TOOLS_DIR:-$HOME/.local/bin}"
mkdir -p "$DEST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

install_tgz() { # nome url sha256 binário-dentro-do-tar
  local name="$1" url="$2" sha="$3" bin="$4"
  echo "-> $name"
  curl -fsSL --retry 3 -o "$WORK/$name.tgz" "$url"
  echo "$sha  $WORK/$name.tgz" | sha256sum -c -
  tar -xzf "$WORK/$name.tgz" -C "$WORK" "$bin"
  install -m 0755 "$WORK/$bin" "$DEST/$name"
}

for tool in "$@"; do
  case "$tool" in
    trivy)
      install_tgz trivy \
        https://github.com/aquasecurity/trivy/releases/download/v0.76.1/trivy_0.76.1_Linux-64bit.tar.gz \
        c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0 trivy ;;
    gitleaks)
      install_tgz gitleaks \
        https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
        551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks ;;
    kustomize)
      install_tgz kustomize \
        https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.3/kustomize_v5.8.3_linux_amd64.tar.gz \
        cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61 kustomize ;;
    kubeconform)
      install_tgz kubeconform \
        https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz \
        9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883 kubeconform ;;
    *)
      echo "ferramenta desconhecida: $tool" >&2; exit 1 ;;
  esac
done

echo "$DEST" >> "${GITHUB_PATH:-/dev/null}"
