#!/usr/bin/env python3
"""Gera o PrometheusRule (Kubernetes) a partir do arquivo de regras do compose.

Fonte única:  deploy/observability/prometheus/rules/coursesphere.rules.yml
Gerado:       deploy/observability/k8s/prometheusrule.yaml

Uso:  python scripts/gen_prometheus_rule.py [--check]
--check (CI): falha se o arquivo gerado estiver desatualizado.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "deploy/observability/prometheus/rules/coursesphere.rules.yml"
TARGET = ROOT / "deploy/observability/k8s/prometheusrule.yaml"

HEADER = """# ARQUIVO GERADO por scripts/gen_prometheus_rule.py — não edite à mão.
# Fonte: deploy/observability/prometheus/rules/coursesphere.rules.yml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: coursesphere
  labels:
    app.kubernetes.io/part-of: coursesphere
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
"""


def render() -> str:
    lines = SOURCE.read_text(encoding="utf-8").splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("groups:"))
    body = "\n".join(("  " + line) if line.strip() else "" for line in lines[start:])
    return HEADER + body.rstrip() + "\n"


def main() -> int:
    content = render()
    if "--check" in sys.argv:
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current != content:
            print(f"{TARGET} desatualizado. Rode: python scripts/gen_prometheus_rule.py")
            return 1
        print("PrometheusRule em dia com as regras do compose.")
        return 0
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(content, encoding="utf-8", newline="\n")
    print(f"gerado {TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
