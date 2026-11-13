#!/usr/bin/env bash
# install-workflows.sh — instala no projeto os workflows do GitHub Actions que a skill mantém.
# A fonte é templates/workflows/ desta skill; .github/workflows/ é cópia gerada. Quem quer
# mudar um workflow muda o template (com bump de versão + CHANGELOG) e reinstala.
#
# Uso: scripts/install-workflows.sh [--project <dir>] [--check]
#   --check   não escreve; falha (exit 1) se .github/workflows/ diverge dos templates.
# Exit codes: 0 = instalados / em dia; 1 = divergência (--check) ou falha; 2 = uso.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TPL_DIR="$SKILL_DIR/templates/workflows"

PROJECT="."; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    *) echo "uso: $0 [--project <dir>] [--check]"; exit 2 ;;
  esac
done
cd "$PROJECT" || { echo "FAIL  projeto não existe: $PROJECT"; exit 2; }
[ -f wrangler.jsonc ] || { echo "FAIL  wrangler.jsonc ausente — rodar init-site.sh antes"; exit 2; }

WORKER="$(node "$SCRIPT_DIR/lib/site-config.mjs" get name)"
[ -n "$WORKER" ] || { echo "FAIL  nome do Worker não encontrado no wrangler.jsonc"; exit 1; }
# caminho da skill relativo à raiz do projeto, como os workflows o chamam
SKILL_REL="$(node -e 'const p=require("path");process.stdout.write(p.relative(process.cwd(),process.argv[1])||".")' "$SKILL_DIR")"

render() { sed -e "s|__WORKER__|$WORKER|g" -e "s|__SKILL__|$SKILL_REL|g" "$1"; }

DRIFT=0
for T in "$TPL_DIR"/*.yml; do
  NAME="$(basename "$T")"; DEST=".github/workflows/$NAME"
  if [ "$CHECK" = "1" ]; then
    if [ -f "$DEST" ] && render "$T" | diff -q - "$DEST" >/dev/null; then echo "PASS  $DEST em dia com a skill"
    else echo "FAIL  $DEST ausente ou diferente do template da skill — rodar scripts/install-workflows.sh"; DRIFT=1; fi
  else
    mkdir -p .github/workflows
    render "$T" > "$DEST" && echo "PASS  $DEST instalado"
  fi
done

[ "$CHECK" = "1" ] && exit "$DRIFT"
echo
echo "INSTALL-WORKFLOWS: OK. Commitar .github/workflows/ e configurar o repositório"
echo "(secret e variáveis) conforme references/primeiro-deploy.md."
