#!/usr/bin/env bash
# backup-point.sh — cria o ponto de recuperação ANTES de qualquer migration/deploy.
# Segue a doc oficial de backups: bookmark Time Travel + (opcional) sync R2 + hash do artefato.
# Uso: scripts/backup-point.sh [--project <dir>]
# Exit codes: 0 = ponto criado; 1 = falha ao criar; 3 = D1 inacessível (NÃO migrar).
set -euo pipefail

PROJECT="."
[ "${1:-}" = "--project" ] && PROJECT="${2:-.}"
cd "$PROJECT" || { echo "FAIL: projeto não existe"; exit 1; }

DB_NAME="${EMDASH_D1_NAME:-$(node -e '
  const fs=require("fs");
  const t=fs.readFileSync("wrangler.jsonc","utf8").replace(/\/\/.*$/gm,"");
  const m=t.match(/"database_name":\s*"([^"]+)"/);
  console.log(m?m[1]:"my-emdash-site");
' 2>/dev/null || echo my-emdash-site)}"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="backups/${STAMP}"
mkdir -p "$OUT_DIR"

echo "== Backup point ${STAMP} — D1: ${DB_NAME} =="

# 1. Bookmark Time Travel (recovery point oficial para D1)
if ! npx wrangler d1 time-travel info "$DB_NAME" --json > "${OUT_DIR}/time-travel.json" 2>"${OUT_DIR}/time-travel.err"; then
  echo "FAIL: não foi possível obter o bookmark Time Travel do D1 '${DB_NAME}'."
  echo "      Sem bookmark registrado, NÃO migrar (migrations são forward-only)."
  exit 3
fi
BOOKMARK=$(jq -r '.bookmark // .result.bookmark // empty' "${OUT_DIR}/time-travel.json" 2>/dev/null || true)
echo "PASS  bookmark Time Travel: ${BOOKMARK:-<ver time-travel.json>}"
echo "      (retenção: 7 dias Free / 30 dias Paid — janela maior exige dump SQL offsite)"

# 2. Estado do artefato (pareamento artefato↔banco exigido pela doc de migrations)
git rev-parse HEAD > "${OUT_DIR}/git-commit.txt" 2>/dev/null || echo "no-git" > "${OUT_DIR}/git-commit.txt"
git status --porcelain > "${OUT_DIR}/git-status.txt" 2>/dev/null || true
[ -f .emdash/migrations.json ] && cp .emdash/migrations.json "${OUT_DIR}/migrations.json" \
  && echo "PASS  manifest de migrations copiado" \
  || echo "WARN  .emdash/migrations.json ausente (rodar build antes de migrar)"

# 3. Sync R2 (opcional — exige AWS CLI e credenciais read-only configuradas)
if [ "${EMDASH_CICD_R2_BACKUP:-0}" = "1" ] && command -v aws >/dev/null 2>&1; then
  BUCKET=$(node -e '
    const fs=require("fs");
    const t=fs.readFileSync("wrangler.jsonc","utf8").replace(/\/\/.*$/gm,"");
    const m=t.match(/"bucket_name":\s*"([^"]+)"/);
    console.log(m?m[1]:"");
  ' 2>/dev/null || true)
  if [ -n "$BUCKET" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    echo "INFO  sincronizando R2 '${BUCKET}' (fora da conta de produção)..."
    aws s3 sync "s3://${BUCKET}" "${OUT_DIR}/r2-media" \
      --endpoint-url "https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com" \
      && echo "PASS  backup de objetos R2" \
      || echo "WARN  sync R2 falhou (ver credenciais read-only)"
  else
    echo "WARN  sync R2 pulado: bucket ou CLOUDFLARE_ACCOUNT_ID ausente"
  fi
else
  echo "INFO  sync R2 pulado (EMDASH_CICD_R2_BACKUP=1 para incluir)"
fi

# 4. Lembrete da encryption key (nunca está no D1/R2)
echo "WARN  EMDASH_ENCRYPTION_KEY: backup da lista de rotação é separado (secret manager)."

echo
echo "BACKUP POINT OK → ${OUT_DIR}/"
echo "Guarde este diretório com o run record do deploy. Restore: wrangler d1 time-travel restore ${DB_NAME} --bookmark=<bookmark>"
