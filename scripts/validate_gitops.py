#!/usr/bin/env python3
"""Valida tudo que o ArgoCD vai aplicar, sem precisar de um cluster.

1. Renderiza o app-of-apps (deploy/argocd/root).
2. Para cada Application com chart Helm: `helm template` com os MESMOS
   valores e versão fixada -> pega valores inválidos (schema do chart).
3. Para cada Application do Git: `kustomize build`.
4. Valida tudo com kubeconform (schemas do Kubernetes + catálogo de CRDs).

Requer helm, kustomize e kubeconform no PATH e PyYAML.
Uso:  python scripts/validate_gitops.py [--charts-dir DIR] [--k8s-version 1.34.0]
"""
import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CRD_CATALOG = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"


def run(cmd, **kw):
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", **kw)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(map(str, cmd))}\n{result.stderr[-3000:]}")
    return result.stdout


def kubeconform(manifest: str, k8s_version: str, label: str) -> bool:
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, encoding="utf-8") as fh:
        fh.write(manifest)
        path = fh.name
    try:
        out = subprocess.run(
            ["kubeconform", "-summary", "-ignore-missing-schemas", "-kubernetes-version", k8s_version,
             "-schema-location", "default", "-schema-location", CRD_CATALOG, path],
            capture_output=True, text=True, encoding="utf-8")
        summary = (out.stdout.strip().splitlines() or ["(sem saída)"])[-1]
        status = "OK  " if out.returncode == 0 else "FAIL"
        print(f"  [{status}] {label:<28} {summary}")
        if out.returncode != 0:
            print(out.stdout[-2000:])
        return out.returncode == 0
    finally:
        os.unlink(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--charts-dir", help="diretório com charts já baixados (helm pull --untar)")
    parser.add_argument("--k8s-version", default="1.34.0")
    args = parser.parse_args()

    root = run(["helm", "template", "root", str(ROOT / "deploy/argocd/root"),
                "--set", "repoURL=https://github.com/example/coursesphere.git"])
    apps = [d for d in yaml.safe_load_all(root) if d and d.get("kind") == "Application"]
    print(f"app-of-apps: {len(apps)} Applications\n")

    ok = True
    for app in apps:
        name, src = app["metadata"]["name"], app["spec"]["source"]
        namespace = app["spec"]["destination"]["namespace"]
        try:
            if "chart" in src:
                with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, encoding="utf-8") as vf:
                    yaml.safe_dump(src["helm"].get("valuesObject") or {}, vf)
                    values = vf.name
                local = Path(args.charts_dir) / src["chart"] if args.charts_dir else None
                chart_ref = [str(local)] if local and local.exists() else [src["chart"], "--repo", src["repoURL"], "--version", src["targetRevision"]]
                manifest = run(["helm", "template", name, *chart_ref, "-n", namespace, "-f", values,
                                "--kube-version", args.k8s_version, "--include-crds"])
                os.unlink(values)
            else:
                manifest = run(["kustomize", "build", str(ROOT / src["path"].replace("deploy/k8s/overlays/kind", "deploy/k8s/overlays/kind"))])
        except RuntimeError as exc:
            print(f"  [FAIL] {name:<28} renderização falhou:\n{exc}")
            ok = False
            continue
        ok &= kubeconform(manifest, args.k8s_version, name)

    # O overlay alternativo também precisa compilar.
    ok &= kubeconform(run(["kustomize", "build", str(ROOT / "deploy/k8s/overlays/kind-local")]), args.k8s_version, "overlay kind-local")

    print("\nTudo válido." if ok else "\nHá erros acima.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
