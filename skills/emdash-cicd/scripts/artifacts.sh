#!/usr/bin/env bash
# artifacts.sh — o repositório principal do projeto no Cloudflare Artifacts (Git dentro da
# própria conta Cloudflare). O GitHub passa a ser espelho e evidência.
#
#   artifacts.sh setup [--namespace <ns>] [--repo <nome>]
#       Cria o repositório no Artifacts se não existir e registra o remote git "artifacts"
#       (URL sem credencial). Idempotente.
#   artifacts.sh push [--to <ramo>] [--mirror <remote>]
#       Envia o HEAD ao Artifacts. Sem --to, usa o nome do ramo atual. Com --mirror, envia
#       depois o mesmo commit ao remote indicado (ex.: origin), como espelho.
#       ATENÇÃO: com o Workers Builds conectado, push em "main" publica em produção.
#   artifacts.sh status
#       Mostra o repositório, o último push e se o HEAD local está no Artifacts.
#
# Credenciais: o token do Artifacts é emitido a cada push, com validade curta, e passado ao
# git por cabeçalho — nunca é gravado na URL do remote, em arquivo ou em log
# (doc Cloudflare: artifacts/api/git-protocol).
# Requer CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID (ou `wrangler login`), com permissão
# de Artifacts, e conta no plano Workers Paid.
# Exit codes: 0 ok; 1 falha; 2 uso; 3 Cloudflare inacessível/não autenticado.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_NAME="artifacts"

CMD="${1:-}"; [ $# -gt 0 ] && shift
NS=""; REPO=""; TO=""; MIRROR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --namespace) NS="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --mirror) MIRROR="${2:-}"; shift 2 ;;
    *) CMD=""; break ;;
  esac
done
case "$CMD" in setup|push|status) ;; *) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "FAIL  não é um repositório git"; exit 2; }
PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
wr() { $PNPM --silent wrangler "$@"; }

# namespace/repo: argumentos > remote já registrado > nome do Worker
URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
if [ -n "$URL" ]; then
  P="${URL#*/git/}"; P="${P%.git}"
  : "${NS:=${P%%/*}}"; : "${REPO:=${P#*/}}"
fi
WORKER="$(node "$SCRIPT_DIR/lib/site-config.mjs" get name 2>/dev/null || true)"
: "${REPO:=$WORKER}"; : "${NS:=$REPO}"
[ -n "$REPO" ] && [ -n "$NS" ] || { echo "FAIL  informe --namespace e --repo (sem wrangler.jsonc para deduzir)"; exit 2; }

# Uma segunda tentativa: a API do Artifacts (beta) às vezes falha na primeira chamada, e
# concluir "não existe" por causa de um soluço levaria a tentar criar o que já existe.
repo_json() {
  wr artifacts repos get "$REPO" --namespace "$NS" --json 2>/dev/null && return 0
  sleep 2; wr artifacts repos get "$REPO" --namespace "$NS" --json 2>/dev/null
}

# Roda git com um token de escrita de vida curta no cabeçalho; o token não aparece em lugar nenhum.
git_with_token() { # <scope> <args do git...>
  local scope="$1"; shift
  local tok
  tok="$(wr artifacts repos issue-token "$REPO" --namespace "$NS" --scope "$scope" --ttl 900 --json 2>/dev/null | jq -r '.plaintext // empty')"
  [ -n "$tok" ] || { echo "FAIL  não foi possível emitir token do Artifacts (permissão de Artifacts no token da Cloudflare?)"; return 3; }
  git -c "http.extraHeader=Authorization: Bearer $tok" "$@"
}

case "$CMD" in
  setup)
    echo "== artifacts setup: $NS/$REPO =="
    wr artifacts namespaces list --json >/dev/null 2>&1 \
      || { echo "FAIL  Artifacts inacessível — conferir credenciais, permissão de Artifacts e plano Workers Paid"; exit 3; }
    INFO="$(repo_json)"
    if [ -n "$INFO" ]; then
      echo "PASS  repositório já existe"
    else
      INFO="$(wr artifacts repos create "$REPO" --namespace "$NS" --default-branch main --json 2>/dev/null | jq 'del(.token)')" \
        && [ -n "$INFO" ] || { echo "FAIL  wrangler artifacts repos create falhou"; exit 1; }
      echo "PASS  repositório criado (ramo padrão: main)"
    fi
    R="$(echo "$INFO" | jq -r '.remote // empty')"
    [ -n "$R" ] || { echo "FAIL  o Artifacts não devolveu a URL do remote"; exit 1; }
    if [ "$URL" = "$R" ]; then echo "PASS  remote git '$REMOTE_NAME' já registrado"
    elif [ -n "$URL" ]; then git remote set-url "$REMOTE_NAME" "$R" && echo "PASS  remote git '$REMOTE_NAME' atualizado"
    else git remote add "$REMOTE_NAME" "$R" && echo "PASS  remote git '$REMOTE_NAME' registrado"; fi
    echo
    echo "ARTIFACTS setup: OK. Próximo: scripts/artifacts.sh push --to main"
    echo "(conectar o Workers Builds a este repositório é um passo no painel — references/artifacts.md)"
    ;;

  push)
    [ -n "$URL" ] || { echo "FAIL  remote '$REMOTE_NAME' não registrado — rodar: scripts/artifacts.sh setup"; exit 2; }
    [ -n "$(git status --porcelain)" ] && echo "WARN  há mudanças não commitadas; só o que está commitado é enviado"
    : "${TO:=$(git rev-parse --abbrev-ref HEAD)}"
    SHA="$(git rev-parse --short HEAD)"
    echo "== artifacts push: $SHA → $NS/$REPO ($TO) =="
    git_with_token write push "$REMOTE_NAME" "HEAD:refs/heads/$TO" || { echo "FAIL  push ao Artifacts falhou"; exit 1; }
    echo "PASS  Artifacts atualizado ($TO = $SHA)"
    if [ -n "$MIRROR" ]; then
      BR="$(git rev-parse --abbrev-ref HEAD)"
      if git push "$MIRROR" "HEAD:refs/heads/$BR"; then echo "PASS  espelho '$MIRROR' atualizado ($BR = $SHA)"
      else echo "WARN  espelho '$MIRROR' NÃO atualizado — o Artifacts está à frente; repetir: git push $MIRROR $BR"; fi
    fi
    ;;

  status)
    INFO="$(repo_json)" || true
    [ -n "$INFO" ] || { echo "MISS  repositório $NS/$REPO não existe (ou Artifacts inacessível) — rodar setup"; exit 1; }
    echo "$INFO" | jq -r '"repositório : \(.name)\nramo padrão : \(.default_branch)\ncriado em   : \(.created_at)\núltimo push : \(.last_push_at // "nunca")"'
    echo "namespace   : $NS"
    [ -n "$URL" ] && echo "remote git  : $REMOTE_NAME registrado" || echo "remote git  : NÃO registrado (rodar setup)"
    if [ -n "$URL" ]; then
      HEADS="$(git_with_token read ls-remote --heads "$REMOTE_NAME" 2>/dev/null)" || true
      LOCAL="$(git rev-parse HEAD)"
      if [ -z "$HEADS" ]; then echo "ramos       : nenhum (repositório vazio)"
      else
        echo "$HEADS" | awk '{sub("refs/heads/","",$2); printf "ramo        : %s = %s\n", $2, substr($1,1,7)}'
        echo "$HEADS" | grep -q "^$LOCAL" && echo "HEAD local  : está no Artifacts" || echo "HEAD local  : AINDA NÃO enviado ($(git rev-parse --short HEAD))"
      fi
    fi
    ;;
esac
