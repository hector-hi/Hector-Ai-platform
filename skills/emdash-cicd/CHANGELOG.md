# CHANGELOG — skill emdash-cicd

Toda mudança nesta skill exige: (1) edição em SKILL.md/scripts/references, (2) bump de `version` no frontmatter do SKILL.md, (3) entrada aqui, na mesma mudança. Format: `Keep a Changelog`, semântica simples MAJOR.MINOR.PATCH (procedimento novo = MINOR, ajuste = PATCH, quebra de contrato de script = MAJOR).

## [1.3.0] — 2026-11-13

Primeira execução real de `preflight.sh` e `gate-local.sh`, contra o site criado neste repositório (EmDash 1.5.0). `backup-point.sh`, `deploy.sh` e `postdeploy.sh` **continuam sem run real** — dependem do primeiro deploy.

### Added
- Workflows do GitHub Actions (`.github/workflows/ci.yml` e `deploy.yml`) que executam os scripts da skill, e a seção 3-A do SKILL.md que os descreve. Fecha a lacuna registrada na 1.2.0.
- Gate `wrangler deploy --dry-run` no CI: confere que o pacote monta e que os bindings estão todos lá, sem publicar.
- `scripts/preflight.sh`: reconhece o wrangler instalado no projeto (antes só o global, e avisava à toa).

### Fixed (achados da execução real)
- `scripts/preflight.sh`: o aviso "backups não está no .gitignore" aparecia mesmo com `backups/` ignorado, porque o padrão só casa com diretório e o diretório não existe antes do primeiro deploy.
- `scripts/preflight.sh`: versão do Node impressa como `vv22…`.
- `scripts/preflight.sh`: em CI não avisa mais da falta de `.env` (lá a chave é secret do Worker).

### Confirmado na execução real
- A correção do gate `emdash doctor` da 1.2.0: no projeto D1 real o doctor reporta `database: not found` e `scheduler wiring: pass`; o gate passa.

### Lacunas conhecidas
- Ambientes nomeados do Wrangler continuam sem suporte (decisão D10).
- Se `wrangler d1 time-travel info --json` devolve o bookmark no campo que `backup-point.sh` lê só o primeiro deploy dirá. A saída inteira é guardada de qualquer forma.

## [1.2.0] — 2026-11-13

Revisão da skill contra o código-fonte do EmDash (CLI `migrate`/`doctor`, `reference/cli.mdx`, `deployment/cloudflare.mdx`, `deployment/core-migrations.mdx`). Nenhuma destas correções veio de um deploy real — vieram de leitura do código e de testes dos scripts contra um projeto-stub; o primeiro run real ainda vai validá-las.

### Fixed
- `scripts/gate-local.sh`: o gate `emdash doctor` falhava em **todo** projeto D1, porque o check `database` do doctor procura um SQLite local (`./data.db`) e o comando sai com 1. A doc upstream registra que essa falha não afeta os checks de scheduler. O gate agora lê `doctor --json`, desconsidera só a falha `database` quando o `wrangler.jsonc` declara `d1_databases`, e exige `scheduler wiring` passando.
- `scripts/deploy.sh`: a checagem de árvore limpa bloqueava o segundo deploy, porque o `backup-point.sh` grava `backups/<ts>/` dentro do projeto. `backups/` e o lock ficam fora da checagem.
- `scripts/deploy.sh`: `pending` do relatório JSON é uma lista de nomes, não um número — a leitura imprimia `[`. Agora conta os itens.
- `scripts/deploy.sh`: mensagem final executava `'n/a'` como comando quando não havia git.
- `scripts/postdeploy.sh`: a URL era inferida como `https://<worker>.workers.dev`, endereço que não existe (falta o subdomínio da conta). Agora `--url`/`EMDASH_DEPLOY_URL` é obrigatória (exit 2).
- `scripts/postdeploy.sh`: o check de cron lia o `wrangler.jsonc` com comentários; um cron comentado passava.
- `scripts/preflight.sh`: a autenticação "modo CI" passava com só uma das duas variáveis; `emdash migrate` exige as duas.

### Added
- `scripts/deploy.sh`: sem terminal interativo e sem `EMDASH_TARGET_FINGERPRINT`, falha (exit 4) **antes** do backup e do build — antes só falharia no meio do deploy.
- `scripts/deploy.sh`: registros de migration desconhecidos (`unknownApplied`) abortam antes de qualquer apply.
- `scripts/postdeploy.sh`: distingue os exit codes 2 (pendentes) e 3 (desconhecidos) do `emdash migrate --check`.
- `scripts/preflight.sh`: avisa se `backups/` e o lock não estão no `.gitignore` do site.
- `references/pipeline-detail.md`: tabela de tradução entre os exit codes do CLI upstream e os da skill.

### Lacunas conhecidas (ainda não incorporadas — dependem de decisão)
- Ambientes nomeados do Wrangler (`--wrangler-env` / `--env` / `CLOUDFLARE_ENV` no build) não são suportados pelos scripts; entram junto com a decisão D10 (staging).
- Não existe workflow do GitHub Actions na skill; o oficial está em `core-migrations.mdx` e entra quando o site existir no repositório.

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
