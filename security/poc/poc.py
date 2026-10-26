#!/usr/bin/env python3
"""Provas de conceito (PoC) das vulnerabilidades do relatório.

Roda contra a versão ORIGINAL (para mostrar a falha) ou a CORRIGIDA (para
mostrar a correção). Só usa a biblioteca padrão do Python 3.9+.

  # versão corrigida (docker compose deste repositório, via balanceador)
  python security/poc/poc.py --base-url http://localhost:8080/api

  # versão original (git checkout v0-original && docker compose up)
  python security/poc/poc.py --base-url http://localhost:3000

  # CI: falha se algum resultado não for o esperado
  python security/poc/poc.py --base-url ... --expect fixed --out security/poc/out/fixed.json

Cada teste cria os próprios usuários (e-mails aleatórios), então não depende
de dados de seed nem afeta contas reais. Use APENAS em ambiente de teste.
"""
import argparse
import json
import secrets
import statistics
import sys
import time
import urllib.error
import urllib.request
from datetime import date, timedelta

VULNERABLE = "VULNERÁVEL"
FIXED = "CORRIGIDO"
SECURE = "PROTEGIDO"          # controle que já funcionava (teste de controle)
INCONCLUSIVE = "INCONCLUSIVO"

# Senha que satisfaz tanto a política antiga (>= 6) quanto a nova (>= 12, não comum).
STRONG_PASSWORD = "Poc-" + secrets.token_urlsafe(10) + "-Ok!"


class Client:
    def __init__(self, base_url, verbose=False):
        self.base = base_url.rstrip("/")
        self.verbose = verbose
        self.log = []

    def request(self, method, path, body=None, token=None, retry_429=True):
        url = self.base + path
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Accept": "application/json"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        attempts = 4 if retry_429 else 1
        for attempt in range(attempts):
            req = urllib.request.Request(url, data=data, method=method, headers=headers)
            started = time.perf_counter()
            try:
                with urllib.request.urlopen(req, timeout=20) as resp:
                    status, raw, resp_headers = resp.status, resp.read(), dict(resp.headers)
            except urllib.error.HTTPError as err:
                status, raw, resp_headers = err.code, err.read(), dict(err.headers)
            elapsed = time.perf_counter() - started
            text = raw.decode("utf-8", errors="replace")
            if status == 429 and retry_429 and attempt < attempts - 1:
                # Rate limit (Nginx ou API) — espera e tenta de novo, para não
                # confundir proteção de borda com o resultado do teste.
                time.sleep(7)
                continue
            break
        try:
            payload = json.loads(text) if text else None
        except ValueError:
            payload = None
        entry = {"request": f"{method} {path}", "status": status, "elapsed_ms": round(elapsed * 1000, 1),
                 "response_excerpt": text[:300]}
        self.log.append(entry)
        if self.verbose:
            print(f"    {method:6} {path:<40} -> {status} ({entry['elapsed_ms']} ms)")
        return status, payload, text, elapsed, resp_headers


def new_email(prefix):
    return f"{prefix}-{secrets.token_hex(4)}@poc.example.com"


def signup(c, prefix):
    email = new_email(prefix)
    status, payload, *_ = c.request("POST", "/signup", {
        "name": f"PoC {prefix}", "email": email, "password": STRONG_PASSWORD, "password_confirmation": STRONG_PASSWORD})
    if status != 201 or not payload or "token" not in payload:
        raise RuntimeError(f"cadastro falhou ({status}); a API está no ar e acessível em {c.base}?")
    return email, payload["token"]


def create_course(c, token):
    status, payload, *_ = c.request("POST", "/courses", {"course": {
        "name": "Curso PoC " + secrets.token_hex(3), "description": "criado pelo PoC",
        "start_date": str(date.today()), "end_date": str(date.today() + timedelta(days=30))}}, token)
    if status != 201:
        raise RuntimeError(f"criação de curso falhou ({status})")
    return payload["id"]


def result(vid, title, verdict, evidence):
    return {"id": vid, "title": title, "verdict": verdict, "evidence": evidence}


# ---------------------------------------------------------------- testes

def check_draft_lessons(c, ctx):
    """VULN-01: aluno lê aula em rascunho de curso alheio."""
    course_id = create_course(c, ctx["creator_token"])
    status, lesson, *_ = c.request("POST", f"/courses/{course_id}/lessons",
                                   {"lesson": {"title": "Rascunho secreto do PoC", "status": "draft"}}, ctx["creator_token"])
    lesson_id = lesson["id"]
    s_list, listing, *_ = c.request("GET", f"/courses/{course_id}/lessons", token=ctx["other_token"])
    s_show, *_ = c.request("GET", f"/lessons/{lesson_id}", token=ctx["other_token"])
    in_list = s_list == 200 and any(item.get("id") == lesson_id for item in (listing or []))
    leaked = in_list or s_show == 200
    return result("VULN-01", "Aula em rascunho visível para outro usuário",
                  VULNERABLE if leaked else FIXED,
                  f"outro usuário: GET /courses/{course_id}/lessons -> {s_list} (rascunho na lista: {in_list}); "
                  f"GET /lessons/{lesson_id} -> {s_show}")


def check_course_idor(c, ctx):
    """Controle: usuário editar curso de outro criador (já era protegido)."""
    course_id = create_course(c, ctx["creator_token"])
    s_put, *_ = c.request("PUT", f"/courses/{course_id}", {"course": {"name": "Invadido pelo PoC"}}, ctx["other_token"])
    s_del, *_ = c.request("DELETE", f"/courses/{course_id}", token=ctx["other_token"])
    ok = s_put == 403 and s_del == 403
    return result("CONTROLE", "Editar/excluir curso de outro criador (IDOR)",
                  SECURE if ok else VULNERABLE, f"PUT -> {s_put}, DELETE -> {s_del} (esperado 403)")


def check_logout_revocation(c, ctx):
    """VULN-02: token continua válido depois do logout."""
    s_login, payload, *_ = c.request("POST", "/login", {"email": ctx["creator_email"], "password": STRONG_PASSWORD})
    if s_login != 200:
        return result("VULN-02", "JWT continua válido após logout", INCONCLUSIVE, f"login -> {s_login}")
    token = payload["token"]
    s_out, *_ = c.request("DELETE", "/logout", token=token)
    s_me, *_ = c.request("GET", "/me", token=token)
    return result("VULN-02", "JWT continua válido após logout",
                  VULNERABLE if s_me == 200 else FIXED,
                  f"DELETE /logout -> {s_out}; GET /me com o mesmo token -> {s_me}")


def check_default_credentials(c, ctx):
    """VULN-04: contas do seed com senha publicada no README."""
    status, *_ = c.request("POST", "/login", {"email": "tech@coursesphere.com", "password": "password123"})
    return result("VULN-04", "Credenciais padrão do seed (tech@coursesphere.com / password123)",
                  VULNERABLE if status == 200 else FIXED, f"POST /login -> {status}")


def check_debug_exposure(c, ctx):
    """VULN-05: modo development em execução (stack traces, /rails/info)."""
    s_info, _, text_info, *_ = c.request("GET", "/rails/info/properties")
    s_err, _, text_err, *_ = c.request("GET", "/lessons/999999999", token=ctx["creator_token"])
    info_open = s_info == 200 and "Rails version" in text_info
    trace = any(marker in text_err for marker in ("traces", "Application Trace", "Full Trace", "backtrace"))
    return result("VULN-05", "Modo development exposto (stack trace / /rails/info)",
                  VULNERABLE if (info_open or trace) else FIXED,
                  f"GET /rails/info/properties -> {s_info} (aberto: {info_open}); "
                  f"GET /lessons/999999999 -> {s_err} (stack trace na resposta: {trace})")


def check_javascript_url(c, ctx):
    """VULN-06: API aceita video_url com esquema javascript:."""
    course_id = create_course(c, ctx["creator_token"])
    payload = {"lesson": {"title": "Aula XSS PoC", "status": "published", "video_url": "javascript:alert(document.domain)"}}
    status, *_ = c.request("POST", f"/courses/{course_id}/lessons", payload, ctx["creator_token"])
    return result("VULN-06", "video_url aceita javascript: (XSS armazenado latente)",
                  VULNERABLE if status == 201 else FIXED, f"POST lesson com video_url=javascript:... -> {status}")


def check_login_timing(c, ctx, samples=3):
    """VULN-08: tempo de resposta do login revela se o e-mail existe."""
    existing, missing = [], []
    for _ in range(samples):
        s1, *_, t1, _ = c.request("POST", "/login", {"email": ctx["creator_email"], "password": "senha-errada-poc"})
        s2, *_, t2, _ = c.request("POST", "/login", {"email": new_email("naoexiste"), "password": "senha-errada-poc"})
        if s1 == 401:
            existing.append(t1 * 1000)
        if s2 == 401:
            missing.append(t2 * 1000)
    if not existing or not missing:
        return result("VULN-08", "Enumeração de usuários pelo tempo do login", INCONCLUSIVE, "amostras insuficientes (rate limit?)")
    m_exist, m_missing = statistics.median(existing), statistics.median(missing)
    leaky = (m_exist - m_missing) > 80 and m_exist > 3 * m_missing
    return result("VULN-08", "Enumeração de usuários pelo tempo do login",
                  VULNERABLE if leaky else FIXED,
                  f"mediana e-mail existente = {m_exist:.0f} ms; e-mail inexistente = {m_missing:.0f} ms")


def check_weak_password(c, ctx):
    """VULN-09: cadastro aceita senha '123456'."""
    status, *_ = c.request("POST", "/signup", {"name": "Fraca", "email": new_email("fraca"),
                                               "password": "123456", "password_confirmation": "123456"})
    if status == 429:
        return result("VULN-09", "Senha fraca aceita no cadastro", INCONCLUSIVE, "429 (rate limit de cadastro)")
    return result("VULN-09", "Senha fraca aceita no cadastro ('123456')",
                  VULNERABLE if status == 201 else FIXED, f"POST /signup com senha 123456 -> {status}")


def check_brute_force(c, ctx, attempts=12):
    """VULN-03: tentativas ilimitadas de login."""
    email, _ = signup(c, "vitima")
    statuses = []
    for i in range(attempts):
        s, *_ = c.request("POST", "/login", {"email": email, "password": f"chute-{i}"}, retry_429=False)
        statuses.append(s)
    # Senha correta logo depois da rajada
    s_ok, *_ = c.request("POST", "/login", {"email": email, "password": STRONG_PASSWORD}, retry_429=False)
    throttled = 429 in statuses or s_ok == 429
    locked = s_ok == 401
    unprotected = all(s == 401 for s in statuses) and s_ok == 200
    verdict = VULNERABLE if unprotected else (FIXED if (throttled or locked) else INCONCLUSIVE)
    return result("VULN-03", "Sem proteção contra força bruta no login", verdict,
                  f"{attempts} senhas erradas -> {statuses}; senha correta em seguida -> {s_ok} "
                  f"(429 = rate limit; 401 = conta bloqueada)")


CHECKS = [
    ("VULN-01", check_draft_lessons),
    ("CONTROLE", check_course_idor),
    ("VULN-02", check_logout_revocation),
    ("VULN-04", check_default_credentials),
    ("VULN-05", check_debug_exposure),
    ("VULN-06", check_javascript_url),
    ("VULN-08", check_login_timing),
    ("VULN-09", check_weak_password),
    ("VULN-03", check_brute_force),   # por último: dispara rate limit/bloqueio
]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default="http://localhost:8080/api")
    parser.add_argument("--only", help="lista separada por vírgula, ex.: VULN-01,VULN-02")
    parser.add_argument("--expect", choices=["fixed", "vulnerable"], help="sai com código 1 se algum resultado divergir")
    parser.add_argument("--out", help="grava resultados + requisições em JSON")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    c = Client(args.base_url, verbose=args.verbose)
    print(f"Alvo: {c.base}\n")
    try:
        creator_email, creator_token = signup(c, "criador")
        _, other_token = signup(c, "aluno")
    except (urllib.error.URLError, RuntimeError) as exc:
        print(f"Não foi possível preparar o teste: {exc}")
        print("Suba o ambiente primeiro (docker compose up -d) e confira o --base-url.")
        return 2
    ctx = {"creator_email": creator_email, "creator_token": creator_token, "other_token": other_token}

    selected = set(args.only.split(",")) if args.only else None
    results = []
    for vid, fn in CHECKS:
        if selected and vid not in selected:
            continue
        try:
            res = fn(c, ctx)
        except Exception as exc:  # noqa: BLE001 - PoC: registra e segue
            res = result(vid, fn.__doc__.strip().split(":")[0], INCONCLUSIVE, f"erro: {exc}")
        results.append(res)
        print(f"[{res['verdict']:<12}] {res['id']:<9} {res['title']}\n{'':15}{res['evidence']}\n")

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump({"target": c.base, "results": results, "requests": c.log}, fh, ensure_ascii=False, indent=2)
        print(f"Resultados gravados em {args.out}")

    if args.expect:
        want = FIXED if args.expect == "fixed" else VULNERABLE
        wrong = [r for r in results if r["id"] != "CONTROLE" and r["verdict"] not in (want,)]
        control_broken = [r for r in results if r["id"] == "CONTROLE" and r["verdict"] != SECURE]
        if wrong or control_broken:
            print(f"\nResultados fora do esperado ({want}): {[r['id'] for r in wrong + control_broken]}")
            return 1
        print(f"\nTodos os resultados conferem com o esperado: {want}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
