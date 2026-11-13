#!/usr/bin/env bash
# init-site.sh — cria o site EmDash (um Worker) num diretório, pronto para o pipeline.
#
# O que faz, na ordem:
#   1. obtém o template oficial — pelo scaffolder (`npm create emdash@latest`) ou, se ele
#      não alcançar a rede, de uma cópia local do repositório do EmDash (--from-upstream);
#   2. aplica os nomes de produção (Worker, D1, R2);
#   3. liga o sandbox de plugins (a menos de --no-sandbox);
#   4. põe as evidências do pipeline no .gitignore;
#   5. instala as dependências.
# Não provisiona nada na Cloudflare — isso é provision.sh.
#
# Uso: scripts/init-site.sh --name <worker> [--dir <dir>] [--template starter|blog|marketing|portfolio]
#                           [--bucket <nome>] [--no-sandbox] [--no-install]
#                           [--from-upstream <checkout do emdash-cms/emdash>]
# Exit codes: 0 = site criado; 1 = falha; 2 = uso incorreto ou site já existe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/lib/site-config.mjs"

NAME=""; DIR="."; TEMPLATE="starter"; BUCKET=""; SANDBOX=1; INSTALL=1; UPSTREAM=""
usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --template) TEMPLATE="${2:-}"; shift 2 ;;
    --bucket) BUCKET="${2:-}"; shift 2 ;;
    --no-sandbox) SANDBOX=0; shift ;;
    --no-install) INSTALL=0; shift ;;
    --from-upstream) UPSTREAM="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$NAME" ] || usage
case "$TEMPLATE" in starter|blog|marketing|portfolio) ;; *) echo "FAIL  template desconhecido: $TEMPLATE"; exit 2 ;; esac

mkdir -p "$DIR"; DIR="$(cd "$DIR" && pwd)"
[ -f "$DIR/wrangler.jsonc" ] && { echo "FAIL  já existe um site em $DIR (wrangler.jsonc presente) — nada a criar"; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/$NAME"

echo "== init-site: $NAME (template ${TEMPLATE}-cloudflare) =="

# --- 1. Obter o template ---
if [ -n "$UPSTREAM" ]; then
  TPL="$UPSTREAM/templates/${TEMPLATE}-cloudflare"
  [ -f "$TPL/wrangler.jsonc" ] || { echo "FAIL  template não encontrado em $TPL"; exit 1; }
  echo "INFO  copiando de $TPL"
  mkdir -p "$SRC"
  cp -R "$TPL/." "$SRC/"
  rm -rf "$SRC/node_modules" "$SRC/dist" "$SRC/.astro" "$SRC/.wrangler" "$SRC/CHANGELOG.md"
  # versões publicadas no lugar de workspace:* / catalog: (como faz o sync oficial dos templates)
  node "$CFG" resolve-upstream "$UPSTREAM" "${TEMPLATE}-cloudflare" > "$SRC/package.json.new"
  mv "$SRC/package.json.new" "$SRC/package.json"
  node "$CFG" workspace-yaml > "$SRC/pnpm-workspace.yaml"
else
  echo "INFO  rodando o scaffolder oficial (npm create emdash@latest)"
  SB="--sandboxed-plugins"; [ "$SANDBOX" = "1" ] || SB="--no-sandboxed-plugins"
  if ! (cd "$TMP" && npm create emdash@latest -- "$NAME" --template "cloudflare:${TEMPLATE}" --pm pnpm --no-install "$SB" --yes); then
    echo
    echo "FAIL  o scaffolder não concluiu (em ambientes de rede restrita ele não alcança"
    echo "      github.com/emdash-cms/templates). Alternativa equivalente:"
    echo "        git clone --depth 1 https://github.com/emdash-cms/emdash.git <pasta>"
    echo "        $0 --name $NAME --from-upstream <pasta> ..."
    exit 1
  fi
  [ -f "$SRC/wrangler.jsonc" ] || { echo "FAIL  o scaffolder não gerou wrangler.jsonc em $SRC"; exit 1; }
fi

# --- 2. Levar para o destino sem sobrescrever o que já existe ---
SKIPPED=""
while IFS= read -r -d '' F; do
  REL="${F#"$SRC"/}"
  if [ -e "$DIR/$REL" ] || [ -L "$DIR/$REL" ]; then SKIPPED="$SKIPPED $REL"; continue; fi
  mkdir -p "$DIR/$(dirname "$REL")"
  cp -P "$F" "$DIR/$REL"
done < <(find "$SRC" \( -type f -o -type l \) -print0)
# AGENTS.md: se o destino já tinha o seu, o guia do template entra ao final dele.
if [[ " $SKIPPED " == *" AGENTS.md "* ]] && ! grep -q "guia que vem do template" "$DIR/AGENTS.md"; then
  { printf '\n---\n\n# O site EmDash (guia que vem do template `%s-cloudflare`)\n\n' "$TEMPLATE"; cat "$SRC/AGENTS.md"; } >> "$DIR/AGENTS.md"
  echo "INFO  AGENTS.md existente preservado; guia do template acrescentado ao final"
  SKIPPED="${SKIPPED/ AGENTS.md/}"
fi
[ -n "$SKIPPED" ] && echo "WARN  já existiam e NÃO foram sobrescritos:$SKIPPED"

cd "$DIR"

# --- 3. Nomes, sandbox, .gitignore ---
node -e '
  const fs=require("fs"); const p=JSON.parse(fs.readFileSync("package.json","utf8"));
  p.name=process.argv[1]; if (fs.existsSync("seed/seed.json")) p.emdash={label:p.emdash?.label??process.argv[2],...p.emdash,seed:"seed/seed.json"};
  fs.writeFileSync("package.json", JSON.stringify(p,null,2)+"\n");
' "$NAME" "$(printf %s "$TEMPLATE" | sed 's/./\U&/')"
node "$CFG" set-names "$NAME" ${BUCKET:+"$BUCKET"}
if [ "$SANDBOX" = "1" ]; then node "$CFG" enable-sandbox
else echo "INFO  sandbox de plugins desligado (--no-sandbox)"; fi
node "$CFG" ignore-evidence

# --- 4. Dependências ---
if [ "$INSTALL" = "1" ]; then
  PNPM="pnpm"; command -v pnpm >/dev/null 2>&1 || PNPM="npx pnpm"
  echo "== pnpm install =="
  $PNPM install || { echo "FAIL  pnpm install falhou"; exit 1; }
fi

echo
echo "INIT-SITE: OK → $DIR"
echo "Próximo: scripts/provision.sh (cria o D1 e o R2 e fixa o database_id),"
echo "         scripts/install-workflows.sh (CI e Deploy no GitHub Actions),"
echo "         scripts/pipeline.sh check (os mesmos gates que o CI roda)."
