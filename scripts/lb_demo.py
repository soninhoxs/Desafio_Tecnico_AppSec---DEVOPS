#!/usr/bin/env python3
"""Demonstra que o balanceador distribui as requisições entre as réplicas.

Uso:  python scripts/lb_demo.py [--url http://localhost:8080] [-n 20]

Faz N requisições a /api/health/live passando pelo Nginx e conta qual
réplica respondeu (header X-Served-By, ligado no compose com
EXPOSE_INSTANCE_HEADER=true). Saída serve como evidência do item 5 do desafio.
Só biblioteca padrão do Python.
"""
import argparse
import collections
import json
import sys
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost:8080")
    parser.add_argument("-n", type=int, default=20)
    args = parser.parse_args()

    endpoint = f"{args.url.rstrip('/')}/api/health/live"
    counts = collections.Counter()
    print(f"GET {endpoint} x{args.n}\n")
    for i in range(1, args.n + 1):
        with urllib.request.urlopen(endpoint, timeout=5) as resp:
            served_by = resp.headers.get("X-Served-By", "?")
            body = json.loads(resp.read().decode())
        counts[served_by] += 1
        print(f"  #{i:02d} status={resp.status} x-served-by={served_by:<8} body.instance={body.get('instance')}")

    print("\nDistribuição:")
    for instance, total in sorted(counts.items()):
        print(f"  {instance:<8} {total:>3} req  {'#' * total}")

    if len(counts) < 2:
        print("\nATENÇÃO: só uma réplica respondeu — verifique se api-1 e api-2 estão saudáveis.")
        return 1
    print("\nOK: as requisições foram distribuídas entre as réplicas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
