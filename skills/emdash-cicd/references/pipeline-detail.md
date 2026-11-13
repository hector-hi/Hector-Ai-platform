# Detalhe do pipeline — variáveis, códigos de saída e fronteiras

## Mapa estágio → script → skill upstream

| Estágio | Script | Skill upstream base | Bloqueia se falhar? |
|---|---|---|---|
| Criar o site | `init-site.sh` | scaffolder oficial `create-emdash`; `scripts/sync-templates-repo.mjs` (versões) | Sim (exit 1/2) |
| Provisionar | `provision.sh` | `core-migrations.mdx` ("Provision D1 before migrating it") | Sim (exit 1/3) |
| Repositório | `artifacts.sh setup\|push\|status` | doc Cloudflare: Artifacts (git-protocol, wrangler) | Sim (exit 1/3) |
| Workflows | `install-workflows.sh` | — (templates desta skill) | Sim em `--check` (exit 1) |
| **Tudo, em ordem** | **`pipeline.sh check\|status\|deploy`** | orquestra os estágios abaixo; é o que CI e Deploy chamam | Sim — devolve o exit do estágio que falhou |
| Preflight | `preflight.sh` | `building-emdash-site` (bindings/entry point) | Sim (exit 1/2) |
| Dev | `gate-local.sh` | espelha `ci.yml` upstream, adaptado aos scripts que o projeto define (site scaffolded: só typecheck; monorepo/toolchain completa: format, lint, unit, browser, e2e opcional) + `emdash doctor --json` (em D1, a falha `database` é esperada e desconsiderada) | Sim (exit 1) |
| Review | (skill, não script) | `adversarial-reviewer` | Sim — findings Critical/High |
| Acceptance | (skill, não script) | `ux-acceptance-coordinator` + `agent-browser` | Opcional, pré-release |
| Integration | `gate-local.sh` + `emdash types` | `emdash-cli` | Sim |
| Backup | `backup-point.sh` | doc oficial de backups | Sim (exit 3) |
| Deploy | `deploy.sh` | `core-migrations.mdx` (workflow oficial) | Sim (exit 1/3/4) |
| Verify | `postdeploy.sh` | doc de deployment (health/admin/bindings) | Sim (exit 1/5) |
| Retro | `retro.sh` | — (protocolo desta skill) | Sim se gaps não incorporados (exit 6) |

Review e acceptance são executados **pelo agente lendo a skill upstream** — deliberadamente não são scripts: envolvem julgamento. Preflight, gates, backup, deploy, verify e retro são **código**: qualquer agente/humano obtém o mesmo resultado.

## Variáveis de ambiente

| Variável | Usada por | Função |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | backup/deploy | Conta dona do D1 (modo CI) |
| `CLOUDFLARE_API_TOKEN` | backup/deploy | Token com D1 Edit (secret no CI) |
| `EMDASH_TARGET_FINGERPRINT` | deploy | Fingerprint revisado localmente (migrate não-interativo). Sem ela, o migrate é interativo e pede confirmação do alvo |
| `EMDASH_D1_NAME` | backup | Nome do banco (default: lido do wrangler.jsonc) |
| `EMDASH_DEPLOY_URL` | postdeploy | URL pública a verificar — **obrigatória** (ou `--url`). Não há default: o endereço real é `<worker>.<subdomínio-da-conta>.workers.dev` ou o domínio próprio |
| `EMDASH_CICD_ENCRYPTION_KEY` | pipeline (deploy) | Se definida, é enviada ao Worker como secret `EMDASH_ENCRYPTION_KEY` após o deploy. Nome diferente de propósito: assim a chave não entra no ambiente do build |
| `EMDASH_CICD_EVIDENCE_DIR` | pipeline (deploy) | Diretório, fora do checkout, onde os logs são copiados para o CI guardar como artefato |
| `EMDASH_CICD_E2E=1` | gate-local | Inclui `test:e2e` (Playwright) nos gates |
| `EMDASH_CICD_R2_BACKUP=1` | backup | Inclui sync dos objetos R2 (exige AWS CLI + credenciais read-only) |
| `EMDASH_HEADERS` | emdash-cli remoto | Headers de auth para instância atrás de proxy (skill emdash-cli upstream) |

## Códigos de saída (contrato para CI/agentes)

| Código | Significado | Ação esperada |
|---|---|---|
| 0 | OK | Prosseguir |
| 1 | Gate de qualidade/ambiente falhou | Corrigir, re-executar |
| 2 | Uso incorreto do script / projeto inválido / URL ausente no postdeploy | Corrigir invocação |
| 3 | D1 inacessível / backup point falhou | NÃO migrar; investigar credenciais/alvo |
| 4 | Migration falhou ou check divergente | NÃO re-executar às cegas (lock D1 espera 10s e falha; migrations são forward-only) — restaurar bookmark se necessário |
| 5 | Site fora do ar no pós-deploy | Rollback de rota/artefato, investigar |
| 6 | Gaps não incorporados à skill (protocolo Skill Viva) | Atualizar SKILL.md+CHANGELOG e re-rodar retro |

### Códigos do `emdash migrate` (CLI upstream) e como o pipeline os traduz

Os números do CLI e os da skill **não significam a mesma coisa** — quem lê log precisa saber de qual camada veio o código. Fonte: `docs/src/content/docs/reference/cli.mdx` do repositório EmDash.

| Código do CLI | Significado upstream | O que o pipeline faz |
|---|---|---|
| 0 | Sucesso (inclui `--status` bem-sucedido) | Prossegue |
| 1 | Erro de validação, configuração, alvo, migration ou cleanup | `deploy.sh` sai com 1 (no `--status`) ou 4 (no apply) |
| 2 | `--check` achou migrations conhecidas pendentes | `postdeploy.sh` reporta "PENDENTES" e sai com 1 |
| 3 | `--check` achou registros desconhecidos (tem precedência sobre pendentes) | `postdeploy.sh` reporta "DESCONHECIDOS" e sai com 1; `deploy.sh` aborta com 4 já no `--status` |
| 4 | Confirmação ausente/recusada ou fingerprint divergente | `deploy.sh` sai com 4 — e, sem terminal e sem fingerprint, falha com 4 antes do backup |
| 130 | Interrompido após cleanup | Tratar como resultado ambíguo: `emdash migrate --status` no mesmo alvo, nunca reexecutar às cegas |

## Fronteiras intencionais

- **deploy.sh nunca decide sozinho o alvo de migration** — em modo interativo o `emdash migrate` pede confirmação; em modo CI, exige fingerprint revisado. O script só orquestra a sequência oficial.
- **backup é gate, não etapa opcional** — sem bookmark Time Travel registrado, o deploy aborta (exit 3), exceto com `--skip-backup` explícito.
- **evidências do pipeline não sujam a árvore** — `backups/` e `.emdash-cicd-deploy.lock` ficam fora da checagem de árvore limpa e devem estar no `.gitignore` do site (o `preflight.sh` avisa). Os run records em `runs/`, ao contrário, são trilha de auditoria e **são** commitados.
- **a URL do pós-deploy nunca é adivinhada** — verificar o host errado produz um resultado que não diz nada sobre o deploy.
- **lock de concorrência local** (`.emdash-cicd-deploy.lock`) complementa o lock de migration do D1 (10s): migrations do mesmo account+database nunca rodam em paralelo.
- **Não provisionar recursos no deploy** — D1/R2 são provisionados antes (state da infraestrutura); o auto-provision do primeiro `wrangler deploy` é aceitável só para primeiro teste, não para produção corporativa.

## O que este pipeline NÃO cobre (e onde as skills upstream mandam)

- Provisionamento inicial da conta/recursos → usar o Documento de Instalação Integral (fases 1–5).
- Autoria de plugins → skill `creating-plugins`.
- Upgrade de versões EmDash → skill `upgrading-emdash` (work order `.emdash/UPGRADE.md`, backups antes de migrations).
- Jornadas UX → skills `ux-acceptance-coordinator`/`acceptance/tester` com perfis `acceptance/sites/`.
