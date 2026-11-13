# CHANGELOG — skill emdash-cicd

Toda mudança nesta skill exige: (1) edição em SKILL.md/scripts/references, (2) bump de `version` no frontmatter do SKILL.md, (3) entrada aqui, na mesma mudança. Format: `Keep a Changelog`, semântica simples MAJOR.MINOR.PATCH (procedimento novo = MINOR, ajuste = PATCH, quebra de contrato de script = MAJOR).

## [1.1.0] — 2026-11-13

### Changed
- `scripts/gate-local.sh`: gates agora são **adaptados aos scripts que o projeto define** (detecção via package.json). Um site scaffolded (`npm create emdash`) só tem `dev/build/preview/deploy/typecheck` — os gates `format:check`/`lint`/`test:unit`/`test:browser` são do monorepo upstream e de projetos com toolchain completa; ausentes são SKIP com nota, não falha. Antes o script falhava em qualquer site recém-scaffolded por invocar scripts inexistentes.
- SKILL.md estágio 1 e `references/pipeline-detail.md` atualizados para descrever a detecção automática.

### Fixed
- `scripts/retro.sh`: run records de execuções no mesmo segundo não se sobrescrevem mais (sufixo `-2`, `-3`, …).

## [1.0.0] — 2026-11-13

### Added
- SKILL viva com protocolo de atualização obrigatória (seção 4) e validação retro.sh ↔ CHANGELOG.
- Orquestração baseada nas skills oficiais do repositório EmDash: `building-emdash-site`, `emdash-cli`, `creating-plugins`, `adversarial-reviewer`, `agent-browser`, `ux-acceptance-coordinator`, `upgrading-emdash`.
- `scripts/preflight.sh` — ambiente (Node 22+, pnpm, wrangler, jq, git, auth), projeto (wrangler.jsonc, worker.ts), bindings obrigatórios (DB, MEDIA, EmDashRoom, cron), conflito exports×migrations, segredo de criptografia.
- `scripts/gate-local.sh` — gates espelhando `ci.yml` upstream: format:check, lint (oxlint), typecheck, test:unit, test:browser, test:e2e opcional (`EMDASH_CICD_E2E=1`), `emdash doctor` (scheduler wiring). Modo `--fast`.
- `scripts/backup-point.sh` — bookmark Time Travel do D1 + cópia do manifest de migrations + estado git + sync R2 opcional (`EMDASH_CICD_R2_BACKUP=1`).
- `scripts/deploy.sh` — sequência oficial de core-migrations.mdx com lock de concorrência local, guard de árvore limpa, migrate --status/--expected-target-fingerprint/--check e deploy do mesmo artefato.
- `scripts/postdeploy.sh` — health da página pública, `/_emdash/admin/`, `migrate --check` final, bindings efetivos no config gerado (`.wrangler/deploy/config.json`), aviso de latência de ativação do cron.
- `scripts/retro.sh` — run record em `runs/`, validação version↔CHANGELOG, falha (exit 6) se gaps declarados não foram incorporados.
- `references/pipeline-detail.md` — mapa estágio→script→skill upstream, variáveis de ambiente, contrato de exit codes, fronteiras intencionais.

### Sources
- Repositório upstream `emdash-cms/emdash` (skills/, acceptance/, .github/workflows/ci.yml, package.json scripts).
- Documentação oficial de deploy/migrations/backups/sandbox (docs/src/content/docs/…).
