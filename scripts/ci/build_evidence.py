#!/usr/bin/env python3
"""Monta docs/evidencias/execucao/ a partir dos artefatos do workflow E2E.

  python scripts/ci/build_evidence.py <artefatos> <destino> --commit SHA --run-url URL

<artefatos> é a pasta onde o actions/download-artifact extraiu cada artefato
(evidencias-versao-corrigida/, evidencias-versao-original/, zap-baseline/).
Tokens JWT são removidos de todos os arquivos de texto antes de publicar.
Gera um README.md com o resumo (PoC original x corrigido, balanceamento,
resiliência, prints e DAST). Só biblioteca padrão do Python.
"""
import argparse
import datetime as dt
import json
import re
import shutil
import sys
from pathlib import Path

JWT = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
TEXT_SUFFIXES = {".txt", ".json", ".md", ".log"}

# (artefato, arquivo de origem) -> nome publicado
FILES = [
    ("evidencias-versao-original", "poc-original.txt", "poc-versao-original.txt"),
    ("evidencias-versao-original", "poc-original.json", "poc-versao-original.json"),
    ("evidencias-versao-corrigida", "poc-corrigido.txt", "poc-versao-corrigida.txt"),
    ("evidencias-versao-corrigida", "poc-corrigido.json", "poc-versao-corrigida.json"),
    ("evidencias-versao-corrigida", "compose-ps.txt", "compose-ps.txt"),
    ("evidencias-versao-corrigida", "lb-demo.txt", "balanceamento-lb-demo.txt"),
    ("evidencias-versao-corrigida", "lb-access-log.txt", "balanceamento-log-nginx.txt"),
    ("evidencias-versao-corrigida", "api-logs-json.txt", "logs-api-json.txt"),
    ("evidencias-versao-corrigida", "resiliencia-circuit-breaker.txt", "resiliencia-circuit-breaker.txt"),
    ("evidencias-versao-corrigida", "prometheus-requests-por-instancia.json", "prometheus-requests-por-instancia.json"),
    ("evidencias-versao-corrigida", "prometheus-eventos-seguranca.json", "prometheus-eventos-seguranca.json"),
    ("evidencias-versao-corrigida", "prometheus-dependencia-externa.json", "prometheus-dependencia-externa.json"),
    ("evidencias-versao-corrigida", "prometheus-targets.json", "prometheus-targets.json"),
    ("evidencias-versao-corrigida", "headers-frontend.txt", "headers-frontend.txt"),
    ("evidencias-versao-corrigida", "headers-api.txt", "headers-api.txt"),
    ("evidencias-versao-corrigida", "metrics-bloqueado-na-borda.txt", "metrics-bloqueado-na-borda.txt"),
    ("evidencias-versao-corrigida", "app-cursos.png", "app-cursos.png"),
    ("evidencias-versao-corrigida", "app-curso-instrutor.png", "app-curso-instrutor.png"),
    ("evidencias-versao-corrigida", "grafana-dashboard.png", "grafana-dashboard.png"),
    ("zap-baseline", "report_md.md", "zap-baseline.md"),
    ("zap-baseline", "report_json.json", "zap-baseline.json"),
]


def redact(path: Path) -> None:
    if path.suffix in TEXT_SUFFIXES:
        text = path.read_text(encoding="utf-8", errors="replace")
        path.write_text(JWT.sub("<jwt-removido>", text), encoding="utf-8", newline="\n")


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def poc_table(dest: Path) -> list[str]:
    original = load_json(dest / "poc-versao-original.json") or {}
    fixed = load_json(dest / "poc-versao-corrigida.json") or {}
    by_id = {}
    for label, data in (("original", original), ("corrigida", fixed)):
        for item in data.get("results", []):
            by_id.setdefault(item["id"], {"title": item["title"]})[label] = item
    lines = [
        "| ID | Achado | Versão original (`v0-original`) | Versão corrigida |",
        "|---|---|---|---|",
    ]
    order = ["CONTROLE"] + sorted(k for k in by_id if k != "CONTROLE")
    for vid in [k for k in order if k in by_id]:
        row = by_id[vid]
        orig = row.get("original", {}).get("verdict", "—")
        corr = row.get("corrigida", {}).get("verdict", "—")
        lines.append(f"| {vid} | {row['title']} | **{orig}** | **{corr}** |")
    lines += ["", "<details><summary>Evidência de cada teste (requisição → resposta)</summary>", ""]
    for vid in [k for k in order if k in by_id]:
        row = by_id[vid]
        for label in ("original", "corrigida"):
            if label in row:
                lines.append(f"- **{vid} — versão {label}:** {row[label]['evidence']}")
    lines += ["", "</details>"]
    return lines


def lb_summary(dest: Path) -> list[str]:
    lines = []
    demo = dest / "balanceamento-lb-demo.txt"
    if demo.exists():
        text = demo.read_text(encoding="utf-8")
        block = text.split("Distribuição:", 1)[-1] if "Distribuição:" in text else text
        block = block.strip("\n")
        lines += ["Requisições feitas pelo balanceador (`scripts/lb_demo.py`, header `X-Served-By`):", "", "```text", block, "```", ""]
    prom = load_json(dest / "prometheus-requests-por-instancia.json")
    results = (prom or {}).get("data", {}).get("result", [])
    if results:
        lines += ["Total de requisições atendidas por réplica, segundo o Prometheus:", "", "| Réplica | Requisições |", "|---|---|"]
        for item in sorted(results, key=lambda r: r["metric"].get("instance", "")):
            lines.append(f"| {item['metric'].get('instance', '?')} | {float(item['value'][1]):.0f} |")
        lines.append("")
    log = dest / "balanceamento-log-nginx.txt"
    if log.exists():
        sample = [line for line in log.read_text(encoding="utf-8").splitlines() if '"upstream"' in line][-6:]
        if sample:
            lines += ["Trecho do log JSON do Nginx (o campo `upstream` mostra a réplica que atendeu):", "", "```json"]
            lines += [line.split("| ", 1)[-1] for line in sample]
            lines += ["```", ""]
    return lines


def zap_summary(dest: Path) -> list[str]:
    report = load_json(dest / "zap-baseline.json")
    if not report:
        return []
    counts = {}
    for site in report.get("site", []):
        for alert in site.get("alerts", []):
            risk = alert.get("riskdesc", "?").split(" ")[0]
            counts.setdefault(risk, []).append(alert.get("name") or alert.get("alert", "?"))
    lines = ["| Risco | Alertas | Itens |", "|---|---|---|"]
    for risk in ("High", "Medium", "Low", "Informational"):
        names = counts.get(risk, [])
        lines.append(f"| {risk} | {len(names)} | {', '.join(sorted(set(names))) or '—'} |")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifacts")
    parser.add_argument("dest")
    parser.add_argument("--commit", default="")
    parser.add_argument("--run-url", default="")
    args = parser.parse_args()

    artifacts, dest = Path(args.artifacts), Path(args.dest)
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    published = []
    for artifact, name, target in FILES:
        src = artifacts / artifact / name
        if src.exists():
            shutil.copyfile(src, dest / target)
            redact(dest / target)
            published.append(target)

    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    short = args.commit[:7]
    md = [
        "# Evidências da execução automática (E2E)",
        "",
        f"Gerado automaticamente pelo workflow **E2E** em {now}, commit `{short}`"
        + (f" — [execução no GitHub Actions]({args.run_url})." if args.run_url else "."),
        "Não edite à mão: cada push na `main` que passa no E2E substitui esta pasta.",
        "",
        "Ambiente: `docker compose` no runner do GitHub — Nginx na frente de **2 réplicas da API** (`api-1`, `api-2`),",
        "PostgreSQL, Prometheus, Alertmanager e Grafana. A versão original roda a partir da tag `v0-original`.",
        "Tokens JWT foram removidos dos arquivos (`<jwt-removido>`).",
        "",
        "## 1. Vulnerabilidades — versão original × corrigida (`security/poc/poc.py`)",
        "",
        *poc_table(dest),
        "",
        "## 2. Balanceamento de carga entre as réplicas",
        "",
        *lb_summary(dest),
    ]
    if (dest / "resiliencia-circuit-breaker.txt").exists():
        drill = [
            line for line in (dest / "resiliencia-circuit-breaker.txt").read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("{")  # linhas de log JSON ficam no arquivo completo
        ]
        md += [
            "## 3. Tratamento de falhas da dependência externa (timeout, retry, circuit breaker)",
            "",
            "Saída de `bin/rails runner script/resilience_drill.rb` dentro do container `api-1`:",
            "",
            "```text",
            *drill,
            "```",
            "",
        ]
    prints = [p for p in ("app-cursos.png", "app-curso-instrutor.png", "grafana-dashboard.png") if p in published]
    if prints:
        md += ["## 4. Prints", ""]
        captions = {
            "app-cursos.png": "Aplicação: lista de cursos após o login (usuário de demonstração).",
            "app-curso-instrutor.png": "Página do curso; o card do instrutor convidado vem da API (`/api/courses/:id/guest_instructor`).",
            "grafana-dashboard.png": "Grafana: SLOs, requisições por réplica (balanceamento), erros, latência, segurança e dependência externa.",
        }
        for p in prints:
            md += [f"**{captions[p]}**", "", f"![{p}]({p})", ""]
    if (dest / "headers-frontend.txt").exists():
        md += ["## 5. Cabeçalhos de segurança do frontend", "", "```http",
               (dest / "headers-frontend.txt").read_text(encoding="utf-8").strip(), "```", ""]
    zap = zap_summary(dest)
    if zap:
        md += ["## 6. DAST — OWASP ZAP baseline (passivo, sem autenticação)", "", *zap, "",
               "Relatório completo: [`zap-baseline.md`](zap-baseline.md).", ""]
    md += ["## Arquivos", ""] + [f"- [`{name}`]({name})" for name in sorted(published)] + [""]
    (dest / "README.md").write_text("\n".join(md), encoding="utf-8", newline="\n")
    print(f"{len(published)} arquivos publicados em {dest}")
    return 0 if published else 1


if __name__ == "__main__":
    sys.exit(main())
