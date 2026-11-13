#!/usr/bin/env bash
# provision.sh — cria na Cloudflare os dois recursos que o site declara e que NÃO devem
# ser deixados para o auto-provisionamento do primeiro deploy: o banco D1 e o bucket R2.
# Fixa o UUID do D1 no wrangler.jsonc (estado de infraestrutura reproduzível).
#
# Idempotente: recurso que já existe é reaproveitado, nunca recriado nem apagado.
# `emdash migrate` nunca cria banco — por isso este passo vem antes do primeiro deploy
# (doc upstream: deployment/core-migrations.mdx, "Provision D1 before migrating it").
#
# Os nomes vêm do wrangler.jsonc. O KV de sessões (SESSION) não entra aqui: o adapter o
# injeta no build e o Wrangler o cria no primeiro deploy.
#
# Uso: scripts/provision.sh [--project <dir>] [--location <wnam|enam|weur|eeur|apac|oc>] [--check]
#   --check   só relata o que existe; não cria nem altera nada.
# Requer CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID no ambiente, ou `wrangler login`.
# Exit codes: 0 = recursos prontos; 1 = falha; 2 = uso; 3 = Cloudflare inacessível/não autenticado.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/lib/site-config.mjs"

PROJECT="."; LOCATION=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --location) LOCATION="${2:-}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    *) echo "uso: $0 [--project <dir>] [--location <hint>] [--check]"; exit 2 ;;
  esac
done
cd "$PROJECT" || { echo "FAIL  projeto não existe: $PROJECT"; exit 2; }
[ -f wrangler.jsonc ] || { echo "FAIL  wrangler.jsonc ausente — rodar init-site.sh antes"; exit 2; }

PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
DB_NAME="$(node "$CFG" get database_name)"
DB_ID_CFG="$(node "$CFG" get database_id)"
BUCKET="$(node "$CFG" get bucket_name)"
[ -n "$DB_NAME" ] && [ -n "$BUCKET" ] || { echo "FAIL  database_name/bucket_name não encontrados no wrangler.jsonc"; exit 1; }

echo "== provision: D1 '$DB_NAME' · R2 '$BUCKET' =="

# --- D1 ---
LIST="$($PNPM --silent wrangler d1 list --json 2>/dev/null)" || {
  echo "FAIL  não foi possível listar os bancos D1 — conferir CLOUDFLARE_API_TOKEN/CLOUDFLARE_ACCOUNT_ID (ou wrangler login) e a rede"
  exit 3
}
db_uuid() { echo "$LIST" | jq -r --arg n "$DB_NAME" '[.[] | select(.name == $n)][0].uuid // empty' 2>/dev/null; }
DB_ID="$(db_uuid)"

if [ -n "$DB_ID" ]; then
  echo "PASS  D1 '$DB_NAME' já existe ($DB_ID)"
elif [ "$CHECK" = "1" ]; then
  echo "MISS  D1 '$DB_NAME' não existe"
else
  echo "INFO  criando D1 '$DB_NAME'${LOCATION:+ (location $LOCATION)}"
  $PNPM --silent wrangler d1 create "$DB_NAME" ${LOCATION:+--location "$LOCATION"} >/dev/null \
    || { echo "FAIL  wrangler d1 create falhou"; exit 1; }
  LIST="$($PNPM --silent wrangler d1 list --json 2>/dev/null)"
  DB_ID="$(db_uuid)"
  [ -n "$DB_ID" ] || { echo "FAIL  banco criado mas não encontrado na listagem — conferir no painel"; exit 1; }
  echo "PASS  D1 '$DB_NAME' criado ($DB_ID)"
fi

if [ -n "$DB_ID" ]; then
  if [ "$CHECK" = "1" ]; then
    if [ "$DB_ID_CFG" = "$DB_ID" ]; then echo "PASS  wrangler.jsonc aponta para esse banco"
    else echo "MISS  wrangler.jsonc ${DB_ID_CFG:+aponta para outro banco ($DB_ID_CFG)}${DB_ID_CFG:-sem database_id}"; fi
  else
    node "$CFG" set-database-id "$DB_ID" || exit 1
  fi
fi

# --- R2 ---
if $PNPM --silent wrangler r2 bucket info "$BUCKET" >/dev/null 2>&1; then
  echo "PASS  R2 '$BUCKET' já existe"
elif [ "$CHECK" = "1" ]; then
  echo "MISS  R2 '$BUCKET' não existe"
else
  echo "INFO  criando R2 '$BUCKET'"
  $PNPM --silent wrangler r2 bucket create "$BUCKET" >/dev/null \
    || { echo "FAIL  wrangler r2 bucket create falhou (R2 habilitado na conta?)"; exit 1; }
  echo "PASS  R2 '$BUCKET' criado (privado)"
fi

echo
if [ "$CHECK" = "1" ]; then echo "PROVISION --check: concluído (nada foi alterado)."; exit 0; fi
echo "PROVISION: OK."
git diff --quiet -- wrangler.jsonc 2>/dev/null || echo "Atenção: wrangler.jsonc mudou (database_id) — commitar antes do deploy."
