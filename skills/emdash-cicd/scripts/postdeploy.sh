#!/usr/bin/env bash
# postdeploy.sh — verificação pós-deploy: health, admin, schema e bindings.
# Uso: scripts/postdeploy.sh [--project <dir>] [--url <url>]
# Exit codes: 0 = saudável; 1 = verificação falhou; 5 = site fora do ar.
set -uo pipefail

PROJECT="."
URL="${EMDASH_DEPLOY_URL:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    *) echo "uso: $0 [--project <dir>] [--url <url>]"; exit 2 ;;
  esac
done
cd "$PROJECT" || { echo "FAIL: projeto não existe"; exit 1; }

PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

# URL alvo: argumento > env > workers.dev inferido do nome do Worker
if [ -z "$URL" ]; then
  WNAME=$(node -e '
    const fs=require("fs");
    const t=fs.readFileSync("wrangler.jsonc","utf8").replace(/\/\/.*$/gm,"");
    const m=t.match(/"name":\s*"([^"]+)"/); console.log(m?m[1]:"");
  ' 2>/dev/null || true)
  [ -n "$WNAME" ] && URL="https://${WNAME}.workers.dev"
fi
[ -z "$URL" ] && { echo "FAIL: nenhuma URL (use --url ou EMDASH_DEPLOY_URL)"; exit 1; }

echo "== Post-deploy verify: ${URL} =="

# 1. Health da página pública
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${URL%/}/" || echo 000)
case "$CODE" in
  2*|3*) pass "página pública responde (${CODE})" ;;
  000)   fail "sem resposta (timeout/DNS)"; echo "FATAL: site fora do ar"; exit 5 ;;
  *)     fail "página pública com HTTP ${CODE}" ;;
esac

# 2. Admin respondendo (setup wizard ou painel)
ACODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${URL%/}/_emdash/admin/" || echo 000)
case "$ACODE" in
  2*|3*) pass "admin /_emdash/admin/ responde (${ACODE})" ;;
  *)     fail "admin responde ${ACODE} (404/5xx = rota ou deploy inconsistente)" ;;
esac

# 3. Schema verificado (mesmo artefato)
if $PNPM emdash migrate --check --wrangler-config wrangler.jsonc >/dev/null 2>&1; then
  pass "emdash migrate --check (schema em dia)"
else
  fail "migrate --check divergente — migrations pendentes/desconhecidas no banco"
fi

# 4. Bindings efetivos do deploy (lê o config GERADO, não o wrangler.jsonc)
CFG="dist/server/wrangler.json"
if [ -f "$CFG" ] || [ -f ".wrangler/deploy/config.json" ]; then
  GEN=$( [ -f "$CFG" ] && echo "$CFG" || echo ".wrangler/deploy/config.json" )
  for B in '"DB"' '"MEDIA"' '"IMAGES"' '"ASSETS"'; do
    grep -q "$B" "$GEN" && pass "binding ${B//\"/} presente no config gerado" \
                         || fail "binding ${B//\"/} ausente no config gerado ($GEN)"
  done
else
  echo "WARN  config gerado não encontrado — imagens podem sair sem transformação (ver docs: IMAGES)"
fi

# 5. Cron ativo (tail de 2 min é manual; aqui só valida a config local)
grep -qE '"crons":\s*\["\* \* \* \* \*"\]' wrangler.jsonc \
  && pass "cron local configurado (Cloudflare pode levar até 15 min para ativar novo/alterado trigger)" \
  || fail "cron ausente na config local"

echo
if [ "$FAILED" -ne 0 ]; then echo "POSTDEPLOY: FALHOU — não considerar o deploy concluído."; exit 1; fi
echo "POSTDEPLOY: OK — encerrar com scripts/retro.sh."
