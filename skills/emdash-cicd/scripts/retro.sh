#!/usr/bin/env bash
# retro.sh — fecha o ciclo: run record + validação do protocolo Skill Viva.
# Uso: scripts/retro.sh [--project <dir>] [--gaps "<texto>"] [--stages "dev,review,..."] [--note "..."]
# Regras da skill:
#   1. Toda execução do pipeline gera runs/run-<ts>.md com estágios e exit codes.
#   2. Gaps (procedimentos manuais/novos/não cobertos) DEVEM virar atualização da skill.
#   3. A versão do frontmatter do SKILL.md deve constar como última entrada do CHANGELOG.md.
# Exit codes: 0 = run registrado e skill íntegra; 6 = gaps registrados sem atualização da skill.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

GAPS=""; STAGES=""; NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project) cd "$2" || exit 1; shift 2 ;;
    --gaps)   GAPS="$2"; shift 2 ;;
    --stages) STAGES="$2"; shift 2 ;;
    --note)   NOTE="$2"; shift 2 ;;
    *) echo "uso: $0 [--project <dir>] [--gaps <texto>] [--stages <lista>] [--note <texto>]"; exit 2 ;;
  esac
done

TS=$(date -u +%Y%m%dT%H%M%SZ)
RUNS="${SKILL_DIR}/runs"
mkdir -p "$RUNS"
RUN_FILE="${RUNS}/run-${TS}.md"
# Evitar sobrescrever run records de execuções no mesmo segundo
N=1
while [ -e "$RUN_FILE" ]; do N=$((N+1)); RUN_FILE="${RUNS}/run-${TS}-${N}.md"; done

VERSION=$(awk -F': *' '/^version:/ {print $2; exit}' "${SKILL_DIR}/SKILL.md" | tr -d '"' | tr -d ' ')
[ -z "$VERSION" ] && { echo "FAIL: frontmatter sem version: — obrigatório (formato skill viva)"; exit 6; }

cat > "$RUN_FILE" <<EOF
# Run record — ${TS}

- pipeline-version: ${VERSION}
- git-commit: $(git rev-parse --short HEAD 2>/dev/null || echo n/a)
- stages: ${STAGES:-não informado}
- date: $(date -u +%Y-%m-%dT%H:%MZ)

## Notas
${NOTE:-(nenhuma)}

## Gaps encontrados (procedimentos manuais / não cobertos pela skill)
${GAPS:-(nenhum gap declarado)}
EOF

echo "RUN   registrado → ${RUN_FILE#./}"

# --- Validação Skill Viva ---
CHANGELOG="${SKILL_DIR}/CHANGELOG.md"
if [ ! -f "$CHANGELOG" ]; then
  echo "FAIL: CHANGELOG.md ausente — toda mudança da skill exige entrada no changelog"
  exit 6
fi
if ! head -40 "$CHANGELOG" | grep -q "$VERSION"; then
  echo "FAIL: versão do SKILL.md (${VERSION}) não consta no CHANGELOG.md — atualizar ambos juntos"
  echo "      (protocolo: bump version + entrada no CHANGELOG na MESMA mudança)"
  exit 6
fi
echo "PASS  skill viva íntegra (v${VERSION} documentada no CHANGELOG)"

# --- Gaps não incorporados = falha do estágio ---
if [ -n "$GAPS" ]; then
  cat >&2 <<EOF

GAPS PENDENTES DE INCORPORAÇÃO:
${GAPS}

Protocolo Skill Viva (SKILL.md seção 4): antes de encerrar a tarefa, incorporar o gap
(editar SKILL.md e/ou scripts/, bumpar version, registrar no CHANGELOG.md) e re-rodar
retro.sh sem --gaps. Um gap não incorporado é falha do pipeline, não pendência.
EOF
  exit 6
fi

echo "RETRO: OK — pipeline fechado."
