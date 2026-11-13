#!/usr/bin/env bash
# gate-local.sh — gates de qualidade locais, adaptados ao que o projeto define.
# Um site scaffolded (create-emdash) tem: dev, build, preview, deploy, typecheck (astro check).
# Os gates completos (format:check, lint, test:unit, test:browser, test:e2e) existem no
# monorepo upstream e em forks/projetos da empresa com a toolchain completa — o script
# roda CADA gate apenas se o script existir no package.json, e reporta os ausentes.
# Uso: scripts/gate-local.sh [--project <dir>] [--fast]
# Exit codes: 0 = todos os gates aplicáveis verdes; 1 = gate falhou; 2 = uso/projeto inválido.
set -uo pipefail

PROJECT="."
FAST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --fast) FAST=1; shift ;;
    *) echo "uso: $0 [--project <dir>] [--fast]"; exit 2 ;;
  esac
done
cd "$PROJECT" || { echo "FAIL: projeto não existe: $PROJECT"; exit 2; }

PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
FAILED=0

has_script() { # <nome>
  node -e "const s=require('./package.json').scripts||{}; process.exit(s['$1']?0:1)" 2>/dev/null
}

run_gate() { # <nome> <comando...>
  local name="$1"; shift
  echo
  echo "== GATE: $name =="
  if "$@"; then echo "GATE OK  : $name"; else echo "GATE FAIL: $name"; FAILED=1; fi
}

skip_gate() { echo "SKIP  $1 (script ausente no package.json deste projeto)"; }

echo "== EmDash CI/CD gates locais =="

# Gate sempre disponível em qualquer projeto EmDash (astro check)
if has_script typecheck; then run_gate "typecheck" $PNPM run typecheck
else skip_gate "typecheck"; FAILED=1; fi

# Gates da toolchain completa (monorepo upstream / projeto da empresa com lint+tests)
if has_script format:check; then run_gate "format:check" $PNPM run format:check
elif [ "$FAST" != "1" ]; then skip_gate "format:check"; fi
if has_script lint;         then run_gate "lint"         $PNPM run lint
elif [ "$FAST" != "1" ]; then skip_gate "lint"; fi

if [ "$FAST" = "1" ]; then
  echo "(--fast: pulando testes)"
else
  if has_script test:unit;   then run_gate "test:unit"   $PNPM run test:unit;   else skip_gate "test:unit"; fi
  if has_script test:browser;then run_gate "test:browser" $PNPM run test:browser;else skip_gate "test:browser"; fi
  # E2E é opcional por padrão (custo alto); ligar com EMDASH_CICD_E2E=1
  if [ "${EMDASH_CICD_E2E:-0}" = "1" ]; then
    if has_script test:e2e; then run_gate "test:e2e" $PNPM run test:e2e; else skip_gate "test:e2e"; fi
  else
    echo "INFO  test:e2e pulado (EMDASH_CICD_E2E=1 para incluir)"
  fi
fi

# doctor: valida scheduler wiring (Cron Trigger + handler scheduled nos arquivos locais)
if [ -x node_modules/.bin/emdash ] || command -v emdash >/dev/null 2>&1; then
  run_gate "emdash doctor" npx emdash doctor
else
  echo "SKIP  emdash doctor (CLI não instalada)"
fi

echo
echo "Nota: num site recém-scaffolded, typecheck é o único gate aplicável — adicionar"
echo "lint/testes ao projeto da empresa (padrão do monorepo upstream: oxlint, oxfmt, vitest)."
if [ "$FAILED" -ne 0 ]; then echo "GATES: FALHOU — não prosseguir para review/integration."; exit 1; fi
echo "GATES: OK — pronto para REVIEW (skill adversarial-reviewer upstream)."
