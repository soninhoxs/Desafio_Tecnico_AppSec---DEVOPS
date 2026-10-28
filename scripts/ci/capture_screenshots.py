#!/usr/bin/env python3
"""Tira prints do ambiente em execução (evidência visual do E2E).

  python scripts/ci/capture_screenshots.py --out out/

Gera, quando consegue:
  app-cursos.png              lista de cursos depois do login (usuário de demonstração)
  app-curso-instrutor.png     página do curso com o card do instrutor convidado
                              (dado vindo da API, que aplica timeout/retry/circuit breaker)
  grafana-dashboard.png       dashboard "CourseSphere — SLOs, tráfego e segurança"

Lê as senhas do .env gerado por scripts/bootstrap_env.py. Cada print é
independente: uma falha é registrada e não impede os outros (nem o job).
Requer: pip install playwright && python -m playwright install --with-deps chromium
"""
import argparse
import base64
import sys
import traceback
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]


def read_env(path: Path) -> dict:
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def shot_app(browser, base_url: str, email: str, password: str, out: Path) -> None:
    context = browser.new_context(viewport={"width": 1440, "height": 900}, locale="pt-BR")
    page = context.new_page()
    page.goto(f"{base_url}/login", wait_until="networkidle")
    page.fill('input[type="email"]', email)
    page.fill('input[type="password"]', password)
    page.click('button[type="submit"]')
    page.wait_for_url("**/dashboard", timeout=30_000)
    page.wait_for_selector(".course-card", timeout=30_000)
    page.screenshot(path=str(out / "app-cursos.png"), full_page=True)
    print("ok: app-cursos.png")

    page.locator(".course-card .btn-primary-outline").first.click()
    page.wait_for_selector(".instructor-widget", timeout=30_000)
    # Espera o card sair do estado "Carregando perfil..." (dado ou fallback).
    page.wait_for_function("() => !document.querySelector('.loading-instructor')", timeout=30_000)
    page.wait_for_timeout(1500)  # foto do instrutor
    page.screenshot(path=str(out / "app-curso-instrutor.png"), full_page=True)
    print("ok: app-curso-instrutor.png")
    context.close()


def shot_grafana(browser, grafana_url: str, password: str, out: Path) -> None:
    # Viewport alto: o Grafana só desenha os painéis visíveis (lazy loading).
    token = base64.b64encode(f"admin:{password}".encode()).decode()
    context = browser.new_context(
        viewport={"width": 1600, "height": 2400},
        extra_http_headers={"Authorization": f"Basic {token}"},
    )
    page = context.new_page()
    url = f"{grafana_url}/d/coursesphere-overview/?orgId=1&from=now-15m&to=now&kiosk"
    page.goto(url, wait_until="networkidle")
    if "/login" in page.url:  # basic auth recusada: entra pelo formulário
        page.fill('input[name="user"]', "admin")
        page.fill('input[name="password"]', password)
        page.click('button[type="submit"]')
        page.wait_for_load_state("networkidle")
        page.goto(url, wait_until="networkidle")
    page.wait_for_timeout(10_000)  # consultas dos painéis
    page.screenshot(path=str(out / "grafana-dashboard.png"), full_page=True)
    print("ok: grafana-dashboard.png")
    context.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="out")
    parser.add_argument("--app-url", default="http://localhost:8080")
    parser.add_argument("--grafana-url", default="http://localhost:3001")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    env = read_env(ROOT / ".env")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        for name, action in (
            ("app", lambda: shot_app(browser, args.app_url, "tech@coursesphere.com", env["DEMO_USER_PASSWORD"], out)),
            ("grafana", lambda: shot_grafana(browser, args.grafana_url, env["GRAFANA_ADMIN_PASSWORD"], out)),
        ):
            try:
                action()
            except Exception:  # noqa: BLE001 - evidência opcional: registra e segue
                print(f"falhou: print do {name}", file=sys.stderr)
                traceback.print_exc()
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
