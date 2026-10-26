#!/usr/bin/env python3
"""Espera uma URL responder com o status esperado (para scripts e CI).

Uso:  python scripts/wait_for_http.py http://localhost:8080/api/health [--status 200] [--timeout 420]
"""
import argparse
import sys
import time
import urllib.error
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--status", type=int, default=200)
    parser.add_argument("--timeout", type=int, default=420)
    args = parser.parse_args()

    deadline = time.monotonic() + args.timeout
    last = "sem resposta"
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(args.url, timeout=5) as resp:
                code = resp.status
        except urllib.error.HTTPError as err:
            code = err.code
        except (urllib.error.URLError, ConnectionError, TimeoutError) as err:
            code, last = None, str(err)
        if code == args.status:
            print(f"{args.url} -> {code}")
            return 0
        if code is not None:
            last = f"HTTP {code}"
        time.sleep(3)
    print(f"timeout esperando {args.url} (último: {last})", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
