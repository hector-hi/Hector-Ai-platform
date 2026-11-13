#!/usr/bin/env bash
# preflight.sh — valida ambiente, projeto e bindings antes de qualquer estágio do pipeline.
# Uso: scripts/preflight.sh [--project <dir>]
# Exit codes: 0 = pronto; 1 = falha de ambiente/projeto; 2 = falha de bindings/config.
set -uo pipefail

PROJECT="${2:-.}"
[ "${1:-}" = "--project" ] && PROJECT="$2"
cd "$PROJECT" || { echo "FAIL: diretório do projeto não existe: $PROJECT"; exit 1; }

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=$((FAILED+1)); }
warn() { echo "WARN  $1"; }
FAILED=0

echo "== EmDash CI/CD preflight =="

# --- Ambiente ---
command -v node >/dev/null 2>&1 && NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]') \
  && [ "$NODE_MAJOR" -ge 22 ] && pass "Node.js >= 22 (v$(node --version))" \
  || fail "Node.js >= 22 necessário (docs upstream: 22.23.4+)"
command -v pnpm >/dev/null 2>&1 && pass "pnpm $(pnpm --version)" \
  || warn "pnpm não no PATH (usar npx pnpm ou corepack enable)"
command -v wrangler >/dev/null 2>&1 && pass "wrangler CLI" \
  || warn "wrangler não no PATH (npx wrangler)"
command -v jq >/dev/null 2>&1 && pass "jq" || warn "jq ausente (necessário para backup/deploy)"
command -v git >/dev/null 2>&1 && pass "git" || fail "git ausente"

# Auth Cloudflare: token explícito (CI) OU login interativo
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  pass "CLOUDFLARE_API_TOKEN/ACCOUNT_ID definidos (modo CI)"
elif command -v wrangler >/dev/null 2>&1 && wrangler whoami >/dev/null 2>&1; then
  pass "wrangler autenticado (login interativo)"
else
  warn "sem CLOUDFLARE_API_TOKEN e sem wrangler login — deploy/migrate não autorizados"
fi

# --- Projeto ---
[ -f wrangler.jsonc ] && pass "wrangler.jsonc presente" || { fail "wrangler.jsonc ausente"; exit 1; }
[ -f astro.config.mjs ] && pass "astro.config.mjs presente" || fail "astro.config.mjs ausente"
[ -f src/worker.ts ] && pass "src/worker.ts (entry point) presente" || fail "src/worker.ts ausente"
[ -d node_modules ] && pass "node_modules presente (deps instaladas)" || warn "node_modules ausente — rodar pnpm install"

# --- Bindings obrigatórios do template (conforme docs upstream) ---
# Ler o wrangler.jsonc SEM comentários (o template traz worker_loaders comentado —
# um grep direto daria falso positivo, já que a linha comentada contém o binding).
WRANGLER_CLEAN=$(sed 's|//.*$||' wrangler.jsonc 2>/dev/null || true)
check_binding() { # <nome> <regex>
  if echo "$WRANGLER_CLEAN" | grep -qE "$2"; then pass "binding $1"; else fail "binding $1 ausente em wrangler.jsonc"; fi
}
check_binding "DB (D1)"          '"binding":\s*"DB"'
check_binding "MEDIA (R2)"       '"binding":\s*"MEDIA"'
check_binding "EMDASH_ROOMS (DO)" '"class_name":\s*"EmDashRoom"'
echo "$WRANGLER_CLEAN" | grep -qE '"crons":\s*\["\* \* \* \* \*"\]' \
  && pass "Cron Trigger * * * * *" \
  || fail "Cron Trigger ausente (entradas agendadas não publicam sem ele)"
echo "$WRANGLER_CLEAN" | grep -qE '"binding":\s*"LOADER"' \
  && pass "worker_loaders LOADER (sandbox ativo)" \
  || warn "LOADER ausente/comentado — plugins sandboxed/registry ficarão desativados (SANDBOX_NOT_AVAILABLE)"

# exports X migrations não podem coexistir (docs upstream)
echo "$WRANGLER_CLEAN" | grep -q '"exports"' && echo "$WRANGLER_CLEAN" | grep -q '"migrations"' \
  && fail "exports e migrations no mesmo wrangler.jsonc são incompatíveis (docs upstream)" \
  || pass "exports/migrations não conflitam"

# --- Secrets ---
[ -f .env ] && grep -q "EMDASH_ENCRYPTION_KEY" .env \
  && pass "EMDASH_ENCRYPTION_KEY no .env (não commitar)" \
  || warn "EMDASH_ENCRYPTION_KEY ausente no .env (necessária p/ plugin settings encriptados)"

echo
if [ "$FAILED" -gt 0 ]; then
  echo "PREFLIGHT: $FAILED falha(s). Corrigir antes de prosseguir."
  exit 2
fi
echo "PREFLIGHT: OK (avisos não bloqueiam)."
