#!/usr/bin/env bash
# pipeline.sh — o pipeline inteiro num comando. É o que o CI e o Deploy executam, e o
# que se roda localmente: um caminho só, os mesmos checks em todo lugar.
#
#   pipeline.sh check     DEV + INTEGRATION: preflight → build → gates → ensaio de deploy →
#                         integridade da skill → workflows em dia. Não toca na Cloudflare.
#   pipeline.sh status    preflight → build → `emdash migrate --status`. Só leitura: mostra o
#                         alvo de migration e o fingerprint a conferir.
#   pipeline.sh deploy    tudo de `check` e, só se passar: backup → migrate → deploy → check →
#                         secret da chave → verificação pós-deploy → run record.
#
# Um deploy é, portanto, um `check` que passou e seguiu em frente — nunca um caminho à parte.
#
# Uso: scripts/pipeline.sh <check|status|deploy> [--project <dir>] [--url <url>] [--fingerprint <sha256>]
# Ambiente (deploy/status): CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.
#   EMDASH_TARGET_FINGERPRINT   alvo conferido (ou --fingerprint); obrigatório sem terminal
#   EMDASH_DEPLOY_URL           URL a verificar (ou --url); sem ela, usa a que o deploy imprimir
#   EMDASH_CICD_ENCRYPTION_KEY  se definida, é enviada ao Worker como secret EMDASH_ENCRYPTION_KEY
# Exit codes: os do estágio que falhou (ver references/pipeline-detail.md); 2 = uso.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

MODE="${1:-}"; [ $# -gt 0 ] && shift
PROJECT="."; URL="${EMDASH_DEPLOY_URL:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --fingerprint) export EMDASH_TARGET_FINGERPRINT="${2:-}"; shift 2 ;;
    *) MODE=""; break ;;
  esac
done
case "$MODE" in check|status|deploy) ;; *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
cd "$PROJECT" || { echo "FAIL  projeto não existe: $PROJECT"; exit 2; }

PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
LOGDIR="$(mktemp -d)"            # fora do checkout: deploy.sh exige árvore git limpa
STAGES=""; RECORD=0

stage() { # <nome> <comando...>  — roda, registra o exit code, devolve-o
  local name="$1"; shift
  echo; echo "━━━━ $name ━━━━"
  "$@"; local rc=$?
  STAGES="${STAGES:+$STAGES, }$name=$rc"
  [ "$rc" -eq 0 ] || echo "PIPELINE: estágio '$name' falhou (exit $rc)."
  return "$rc"
}

summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat >> "$GITHUB_STEP_SUMMARY"; cat >/dev/null 2>&1 || true; }

finish() {
  local rc=$?
  if [ "$RECORD" = "1" ]; then
    echo; echo "━━━━ retro ━━━━"
    "$SCRIPT_DIR/retro.sh" --stages "$STAGES" \
      --note "pipeline.sh deploy — exit $rc${GITHUB_RUN_ID:+ — GitHub Actions run $GITHUB_RUN_ID}${URL:+ — $URL}" || true
    # evidências para quem roda em CI guardar como artefato
    cp "$LOGDIR"/*.log "${EMDASH_CICD_EVIDENCE_DIR:-$LOGDIR}/" 2>/dev/null || true
  fi
  exit "$rc"
}
trap finish EXIT

dry_run() {
  local out="$LOGDIR/dry-run.log"
  if $PNPM wrangler deploy --dry-run > "$out" 2>&1; then
    sed -n '/Your Worker has access to the following bindings/,/dry-run: exiting/p' "$out"
  else
    tail -40 "$out"; return 1
  fi
}

skill_integrity() {
  local v; v=$(awk -F': *' '/^version:/ {print $2; exit}' "$SKILL_DIR/SKILL.md")
  for f in "$SCRIPT_DIR"/*.sh; do bash -n "$f" || { echo "FAIL  erro de sintaxe em $f"; return 6; }; done
  head -40 "$SKILL_DIR/CHANGELOG.md" | grep -q "\[$v\]" \
    || { echo "FAIL  version $v do SKILL.md não consta no CHANGELOG.md"; return 6; }
  echo "PASS  skill emdash-cicd v$v — scripts íntegros, versão documentada"
}

run_check() {
  stage preflight   "$SCRIPT_DIR/preflight.sh"            || return $?
  stage build       $PNPM build                           || return $?
  stage gates       "$SCRIPT_DIR/gate-local.sh"           || return $?
  stage dry-run     dry_run                               || return $?
  stage skill       skill_integrity                       || return $?
  stage workflows   "$SCRIPT_DIR/install-workflows.sh" --check || return $?
}

need_credentials() {
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then return 0; fi
  if [ -z "${CI:-}" ] && $PNPM --silent wrangler whoami >/dev/null 2>&1; then return 0; fi
  echo "FAIL  sem credenciais da Cloudflare: definir CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID"
  echo "      (no GitHub: secret e variável de mesmo nome — ver references/primeiro-deploy.md)"
  return 3
}

case "$MODE" in
  check)
    run_check || exit $?
    echo; echo "PIPELINE check: OK — $STAGES"
    ;;

  status)
    stage credenciais need_credentials                    || exit $?
    stage preflight   "$SCRIPT_DIR/preflight.sh"          || exit $?
    stage build       $PNPM build                         || exit $?
    echo; echo "━━━━ alvo de migration (só leitura) ━━━━"
    # 2>&1: o CLI escreve o relatório no stderr; sem isso o fingerprint não chega ao log.
    $PNPM --silent emdash migrate --status --wrangler-config wrangler.jsonc 2>&1 | tee "$LOGDIR/status.log"
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "PIPELINE: migrate --status falhou."; exit 1; }
    FP=$(grep -oE 'Target fingerprint: *[0-9a-f]{64}' "$LOGDIR/status.log" | grep -oE '[0-9a-f]{64}' | head -1)
    echo
    echo "Confira a conta e o banco acima. Se forem os seus, este é o fingerprint do alvo:"
    echo "  ${FP:-<não encontrado na saída — ler acima>}"
    echo "Use-o no deploy: variável EMDASH_TARGET_FINGERPRINT, ou o campo 'fingerprint' do workflow."
    { echo "## Alvo de migration"; echo '```'; cat "$LOGDIR/status.log"; echo '```'
      echo "Se a conta e o banco acima são os seus, rode **deploy** com este fingerprint:"; echo; echo "\`${FP:-ver acima}\`"; } | summary
    ;;

  deploy)
    RECORD=1
    stage credenciais need_credentials || exit $?
    run_check || exit $?
    echo; echo "━━━━ deploy ━━━━"
    "$SCRIPT_DIR/deploy.sh" 2>&1 | tee "$LOGDIR/deploy.log"; RC=${PIPESTATUS[0]}
    STAGES="$STAGES, deploy=$RC"
    [ "$RC" -eq 0 ] || { echo "PIPELINE: estágio 'deploy' falhou (exit $RC)."; exit "$RC"; }

    if [ -n "${EMDASH_CICD_ENCRYPTION_KEY:-}" ]; then
      stage secret bash -c 'printf "%s" "$EMDASH_CICD_ENCRYPTION_KEY" | '"$PNPM"' --silent wrangler secret put EMDASH_ENCRYPTION_KEY' || exit $?
    else
      echo; echo "WARN  EMDASH_CICD_ENCRYPTION_KEY não definida — o Worker fica sem EMDASH_ENCRYPTION_KEY;"
      echo "      settings secretos de plugins só funcionam depois que ela existir (ver primeiro-deploy.md)."
    fi

    [ -n "$URL" ] || URL=$(grep -oE 'https://[a-z0-9.-]+\.workers\.dev' "$LOGDIR/deploy.log" | head -1)
    [ -n "$URL" ] || { echo "FAIL  sem URL para verificar — passar --url ou definir EMDASH_DEPLOY_URL"; STAGES="$STAGES, verify=2"; exit 2; }
    stage verify "$SCRIPT_DIR/postdeploy.sh" --url "$URL" || exit $?

    echo; echo "PIPELINE deploy: OK — $URL"
    { echo "## Deploy concluído"; echo; echo "- URL: $URL"; echo "- Admin: ${URL%/}/_emdash/admin/"
      echo "- Estágios: $STAGES"; echo
      echo "**Se este é o primeiro deploy: abra o admin agora e conclua o setup.** A primeira pessoa a terminar vira administradora."; } | summary
    ;;
esac
