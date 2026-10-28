#!/usr/bin/env python3
"""Tira prints do ambiente em execução (evidência visual do E2E).

  python scripts/ci/capture_screenshots.py --out out/

Gera, quando consegue:
  app-cursos.png              lista de cursos depois do login (usuário de demonstração)
  app-curso-instrutor.png     página do curso com o card do instrutor convidado
                              (dado vindo da API, que aplica timeout/retry/circuit breaker)
  grafana-dashboard.png       dashboard "CourseSphere — SLOs, tráfego e segurança"

Entre os dois, abre os outros cursos (tráfego real para o painel da dependência
externa) e espera o Prometheus coletar (--scrape-wait) antes do print do Grafana.

Lê as senhas do .env gerado por scripts/bootstrap_env.py. Cada print é
independente: uma falha é registrada e não impede os outros (nem o job).
Requer: pip install playwright && python -m playwright install --with-deps chromium
"""
import argparse
import base64
import sys
import time
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

    print(f"ok: {visit_other_courses(page, base_url)} outros cursos abertos")
    context.close()


def visit_other_courses(page, base_url: str, limit: int = 6) -> int:
    """Abre a página dos outros cursos, como um usuário navegando.

    Cada curso novo é uma chamada da API à dependência externa (os repetidos
    vêm do cache), o que alimenta a linha "Dependência externa" do Grafana.
    """
    page.goto(f"{base_url}/dashboard", wait_until="networkidle")
    page.wait_for_selector(".course-card", timeout=30_000)
    total = min(page.locator(".course-card").count(), limit)
    visited = 0
    for index in range(1, total):
        try:
            page.goto(f"{base_url}/dashboard", wait_until="networkidle")
            page.wait_for_selector(".course-card", timeout=30_000)
            page.locator(".course-card").nth(index).locator(".btn-primary-outline").first.click()
            page.wait_for_selector(".instructor-widget", timeout=30_000)
            page.wait_for_function("() => !document.querySelector('.loading-instructor')", timeout=30_000)
            visited += 1
        except Exception:  # noqa: BLE001 - tráfego opcional para o painel
            print(f"aviso: curso {index + 1} não abriu", file=sys.stderr)
    return visited


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
    parser.add_argument("--scrape-wait", type=float, default=35, help="segundos entre o tráfego e o print do Grafana")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    env = read_env(ROOT / ".env")

    def wait_for_scrape():
        # O Prometheus coleta a cada 15 s: sem esperar, o tráfego que acabou de
        # acontecer (cursos abertos acima) ainda não aparece nos painéis.
        time.sleep(args.scrape_wait)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        for name, action in (
            ("app", lambda: shot_app(browser, args.app_url, "tech@coursesphere.com", env["DEMO_USER_PASSWORD"], out)),
            ("espera do scrape", wait_for_scrape),
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
