#!/usr/bin/env python3
"""Gera o arquivo .env com segredos aleatórios para o docker compose.

Uso:  python scripts/bootstrap_env.py [--force]

Não sobrescreve um .env existente sem --force. Só usa a biblioteca padrão
do Python (funciona em Windows, Linux e macOS).
"""
import secrets
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"


def main() -> int:
    if ENV_FILE.exists() and "--force" not in sys.argv:
        print(f"{ENV_FILE} já existe. Use --force para gerar novos segredos "
              "(isso invalida sessões e exige recriar o volume do banco).")
        return 0

    values = {
        "POSTGRES_PASSWORD": secrets.token_urlsafe(24),
        "APP_DB_PASSWORD": secrets.token_urlsafe(24),
        "SECRET_KEY_BASE": secrets.token_hex(64),
        "METRICS_TOKEN": secrets.token_urlsafe(32),
        "GRAFANA_ADMIN_PASSWORD": secrets.token_urlsafe(16),
        "ALLOW_DEMO_SEED": "true",
        "DEMO_USER_PASSWORD": "Demo-" + secrets.token_urlsafe(12),
        "APP_VERSION": "local",
    }
    lines = ["# Gerado por scripts/bootstrap_env.py — NÃO commitar."]
    lines += [f"{key}={value}" for key, value in values.items()]
    ENV_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"{ENV_FILE} criado.")
    print(f"  Grafana: admin / {values['GRAFANA_ADMIN_PASSWORD']}")
    print(f"  Usuários de demo: tech@coursesphere.com e design@coursesphere.com / {values['DEMO_USER_PASSWORD']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
