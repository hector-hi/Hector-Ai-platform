#!/usr/bin/env bash
# deploy.sh — pipeline oficial de deploy EmDash (core-migrations.mdx upstream), serializado.
# Sequência: árvore limpa → backup point → build → migrate --status → migrate → wrangler deploy → migrate --check
# Uso: scripts/deploy.sh [--project <dir>] [--skip-backup]
# Exit codes: 0 = deployado e verificado; 1 = falha de gate; 4 = migration falhou (NÃO re-deployar às cegas)
set -euo pipefail

PROJECT="."
SKIP_BACKUP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --skip-backup) SKIP_BACKUP=1; shift ;;
    *) echo "uso: $0 [--project <dir>] [--skip-backup]"; exit 2 ;;
  esac
done
cd "$PROJECT" || { echo "FAIL: projeto não existe"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
LOCK=".emdash-cicd-deploy.lock"

fail() { echo "DEPLOY FAIL: $1"; exit "${2:-1}"; }

# --- Gate 0: árvore limpa (deploy reproduzível) ---
[ -n "$(git status --porcelain 2>/dev/null)" ] \
  && fail "árvore git suja — commitar/stash antes do deploy (deploy reproduzível)" 1
echo "PASS  árvore git limpa"

# --- Gate 1: lock de concorrência (migrations não rodam em paralelo) ---
if [ -f "$LOCK" ]; then
  LOCK_PID=$(cat "$LOCK" 2>/dev/null || echo "?")
  kill -0 "$LOCK_PID" 2>/dev/null && fail "outro deploy em execução (pid $LOCK_PID) — migrations não são concorrentes" 1
  echo "WARN  lock órfão encontrado (pid $LOCK_PID morto) — removendo"
fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
echo "PASS  lock de deploy adquirido (pid $$)"

# --- Gate 2: backup point (bookmark Time Travel) ---
if [ "$SKIP_BACKUP" = "0" ]; then
  "$SCRIPT_DIR/backup-point.sh" --project . || fail "backup point falhou — não migrar sem recovery point" 3
else
  echo "WARN  backup pulado (--skip-backup) — uso por conta e risco"
fi

# --- Gate 3: build (gera .emdash/migrations.json) ---
echo "== build =="
$PNPM build || fail "build falhou" 1
[ -f .emdash/migrations.json ] || fail "build não gerou .emdash/migrations.json" 1
echo "PASS  build + manifest de migrations"

# --- Gate 4: inspecionar alvo (NUNCA migrar sem confirmar o alvo) ---
echo "== migrate --status =="
STATUS=$($PNPM emdash migrate --status --wrangler-config wrangler.jsonc --json 2>/dev/null) \
  || STATUS=$($PNPM emdash migrate --status --wrangler-config wrangler.jsonc) \
  || fail "migrate --status falhou — verificar CLOUDFLARE_ACCOUNT_ID/API_TOKEN e database_id" 1
echo "$STATUS"
PENDING=$(echo "$STATUS" | jq -r '.pending // .summary.pending // empty' 2>/dev/null | head -1 || true)
[ -n "$PENDING" ] && [ "$PENDING" != "0" ] && [ "$PENDING" != "[]" ] \
  && echo "INFO  migrations pendentes: $PENDING" \
  || echo "INFO  nenhuma migration pendente (deploy de código puro)"

# --- Gate 5: aplicar migrations ---
echo "== migrate =="
if [ -n "${EMDASH_TARGET_FINGERPRINT:-}" ]; then
  # Modo CI (não-interativo): exige fingerprint revisado localmente
  $PNPM emdash migrate --wrangler-config wrangler.jsonc \
    --expected-target-fingerprint "$EMDASH_TARGET_FINGERPRINT" \
    || fail "migration falhou — verificar fingerprint e NÃO re-executar às cegas (lock D1 espera 10s e falha)" 4
  echo "PASS  migrations aplicadas (fingerprint conferido)"
else
  # Modo interativo: o comando pergunta confirmação do alvo — o operador/CI deve revisar
  $PNPM emdash migrate --wrangler-config wrangler.jsonc \
    || fail "migration falhou ou foi abortada" 4
  echo "PASS  migrations aplicadas (confirmação interativa)"
fi

# --- Gate 6: deploy do MESMO artefato (não reconstruir entre migration e deploy) ---
echo "== wrangler deploy =="
$PNPM wrangler deploy || fail "deploy falhou" 1
echo "PASS  deploy publicado"

# --- Gate 7: verificação final ---
echo "== migrate --check =="
$PNPM emdash migrate --check --wrangler-config wrangler.jsonc \
  || fail "migrate --check falhou — schema divergente do build; NÃO ignorar" 4
echo "PASS  schema verificado"

URL=$(npx wrangler deployments list 2>/dev/null | grep -oE 'https://[a-z0-9.-]+\.workers\.dev' | head -1 || true)
echo
echo "DEPLOY OK — artefato: $(git rev-parse --short HEAD 2>/dev/null || 'n/a')${URL:+ — URL: $URL}"
echo "Próximo: scripts/postdeploy.sh (health + admin + bindings) e scripts/retro.sh (run record)."
