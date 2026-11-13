---
name: emdash-cicd
description: Orquestrar o pipeline de desenvolvimento, integração e deploy de um site EmDash em Cloudflare Workers, executando os gates de qualidade como código (preflight, gates locais, ponto de backup, deploy com migrations, verificação pós-deploy e retrospectiva). Baseia-se nas skills oficiais do repositório EmDash (building-emdash-site, emdash-cli, adversarial-reviewer, agent-browser, ux-acceptance-coordinator, upgrading-emdash) e as orquestra sem substituí-las. É uma SKILL VIVA: todo procedimento novo descoberto numa execução deve ser incorporado a ela via protocolo de atualização da seção "Skill Viva".
version: 1.1.0
living-skill: true
update-protocol: CHANGELOG-required
upstream-base: emdash-cms/emdash (skills/ e .agents/skills/)
---

# EmDash CI/CD — pipeline vivo de desenvolvimento, integração e deploy

Esta skill é o **contrato executável** do pipeline. As regras estão nos scripts (`scripts/`); os procedimentos estão aqui e nas skills upstream. Qualquer agente (Claude, ChatGPT/Codex, Perplexity Computer, cursor, etc.) que saiba ler skills e executar bash produz o **mesmo resultado de qualidade**, porque os gates são código, não prosa.

## 1. Relação com as skills do repositório EmDash (não substituir, orquestrar)

| Skill upstream (repositório EmDash) | Papel neste pipeline | Quando é invocada |
|---|---|---|
| `building-emdash-site` | Desenvolvimento do site (schema, seeds, queries, render, config de deploy) | Fase DEV — qualquer trabalho no site |
| `emdash-cli` | CLI: migrations, seeds, types, content, auth em CI (service tokens, `EMDASH_HEADERS`) | Fases DEV, INTEGRATION e DEPLOY |
| `creating-plugins` | Autoria de plugins (`definePlugin()`, hooks, sandbox) | Fase DEV — trabalho com plugins |
| `adversarial-reviewer` | Review adversarial de mudanças antes do merge | Fase REVIEW |
| `agent-browser` | Verificação de UI renderizada (loop snapshot→ação→verificação, dev-bypass) | Fase REVIEW/ACCEPTANCE |
| `ux-acceptance-coordinator` + `acceptance/tester` | Jornadas UX black-box com tester isolado | Fase ACCEPTANCE (opcional, pré-release) |
| `upgrading-emdash` | Upgrade de versões EmDash com work order e backups | Fase DEV — upgrades |

**Regra de precedência:** se uma skill upstream descrever um procedimento para o domínio dela, **seguir a upstream**. Esta skill só define ordem, gates e evidências — nunca contradiz as upstreams. Se um conflito for detectado, é um gap a registrar (seção Skill Viva) e o upstream prevalece até a skill ser atualizada.

## 2. Papéis dos agentes (ChatGPT, Claude, Perplexity)

O pipeline é agnóstico de agente; cada papel é uma atribuição, não um produto:

| Papel | Agente sugerido | Tarefa | Entregável |
|---|---|---|---|
| Pesquisa / vigília upstream | Perplexity | Ler docs/commits upstream, bloqueadores (blob-proxy, domínios, mudanças de API), atualizar conhecimento antes de codar | Resumo citado de fatos relevantes à mudança |
| Implementação | Claude Code ou ChatGPT/Codex | Codar seguindo `building-emdash-site`/`creating-plugins`; rodar `gate-local.sh` até passar | Diff + gates verdes |
| Review adversarial | Claude (ou outro, com contexto de código) | Executar a skill `adversarial-reviewer` sobre o diff | Findings por severidade |
| Aceitação de UX | Qualquer agente com browser, via `agent-browser` | Jornadas do `acceptance/journeys` | Relatório + screenshots |
| Deploy | Qualquer agente ou humano CI | `deploy.sh` (o script é a autoridade; o agente só lê saída e decide) | Run record + bookmarks |

## 3. O pipeline (estágios e gates executáveis)

```text
DEV ──▶ REVIEW ──▶ INTEGRATION ──▶ BACKUP ──▶ DEPLOY ──▶ VERIFY ──▶ RETRO
 │        │            │              │          │          │          │
 gate-    adversarial  gate-local   backup-    deploy.sh  postdeploy retro.sh
 local.sh reviewer     (CI local)   point.sh   (migrate   .sh       (run record
 (lint/   (skill       + doctor     (Time      + deploy   (health +  + gaps →
 type/    upstream)    + e2e        Travel +   seriali-   migrate    CHANGELOG)
 test)                 opcional     R2)       zado)      --check)
```

### Estágio 1 — DEV (`scripts/gate-local.sh`)
Roda os gates de qualidade que o projeto define (detecção automática via package.json): `typecheck` (sempre disponível — `astro check`), e quando a toolchain completa existir (monorepo upstream ou projeto da empresa com oxlint/oxfmt/vitest): `format:check`, `lint`, `test:unit`, `test:browser`, `test:e2e` (opcional via `EMDASH_CICD_E2E=1`), mais `emdash doctor` (scheduler wiring). Gates ausentes são reportados como SKIP, não como falha. Nenhum commit de feature passa com gate vermelho.

### Estágio 2 — REVIEW (`adversarial-reviewer` upstream)
Executar a skill upstream sobre o diff. Findings Critical/High bloqueiam; Medium/Low viram issues. O padrão de findings (invariante violado, local, gatilho, consequência, correção) é o da upstream.

### Estágio 3 — INTEGRATION
`gate-local.sh` completo + branch atualizada + `emdash types` regenerados se o schema mudou (via `emdash-cli` upstream). Commit do manifest `.emdash/migrations.json` fica fora (gitignored pelo template).

### Estágio 4 — BACKUP (`scripts/backup-point.sh`)
Ponto de recuperação ANTES de qualquer migration: bookmark Time Travel do D1 + sync R2 opcional + hash do artefato. Sem bookmark registrado, o deploy não prossegue.

### Estágio 5 — DEPLOY (`scripts/deploy.sh`)
Sequência oficial (core-migrations.mdx upstream), serializada por lock: build → `emdash migrate --status` → migrate (fingerprint em modo não-interativo) → `wrangler deploy` do MESMO artefato → `emdash migrate --check`. Guarda de árvore limpa e de segredo `EMDASH_ENCRYPTION_KEY`.

### Estágio 6 — VERIFY (`scripts/postdeploy.sh`)
Health do URL público, `/_emdash/admin/` respondendo, `migrate --check` final, verificação de bindings (via `.wrangler/deploy/config.json`).

### Estágio 7 — RETRO (`scripts/retro.sh`)
Toda execução termina com um run record em `runs/`. Se surgiram procedimentos novos, comandos manuais não previstos, erros não cobertos pelos gates ou decisões ad-hoc, isto É um gap: aplicar o Protocolo Skill Viva abaixo ANTES de encerrar a tarefa.

## 4. Skill Viva — protocolo de atualização (parte do formato, não opcional)

Esta skill nasce com qualidade porque os gates são código; **permanece** com qualidade porque se atualiza a cada execução. O formato é aberto a mudanças por design:

1. **Toda execução registra um run** (`scripts/retro.sh` → `runs/run-<timestamp>.md`) com: estágios executados, exit codes, gaps encontrados.
2. **Gap = qualquer coisa feita manualmente que não estava descrita ou scriptada aqui** (um comando novo, um check improvisado, um erro cujo diagnóstico não estava na skill, um procedimento upstream que mudou).
3. **Todo gap confirmado deve ser incorporado** na mesma sessão: editar `SKILL.md` (ou criar/ajustar script em `scripts/`), bumpar `version` no frontmatter e adicionar entrada em `CHANGELOG.md` (data, versão, o que mudou, por quê). O `retro.sh` falha o estágio final se a versão do frontmatter não constar como última entrada do CHANGELOG.
4. **Precedência upstream:** mudanças nas skills do repositório EmDash (novas versões via `upgrade-emdash`, que atualiza as skills do projeto) devem ser refletidas aqui na execução seguinte que as tocar.
5. **Nada é removido sem registro:** scripts aposentados ficam marcados no CHANGELOG, não deletados silenciosamente.
6. **Formato aberto:** novas seções, novos scripts e novas referências são esperados; a única restrição é que (a) regras executáveis vão para scripts, (b) procedimentos e critérios ficam no SKILL.md, (c) contexto longo fica em `references/`, e (d) toda mudança passa pelo CHANGELOG.

## 5. Referências

| Arquivo | Conteúdo |
|---|---|
| [references/pipeline-detail.md](references/pipeline-detail.md) | Detalhe de cada estágio, variáveis de ambiente e códigos de saída |
| [CHANGELOG.md](CHANGELOG.md) | Histórico versionado da skill (obrigatório em toda mudança) |
| `runs/` | Run records gerados por `retro.sh` |
| Skills upstream | `skills/` do repositório EmDash e `.agents/skills/` do template |

## 6. Comandos rápidos

```bash
scripts/preflight.sh                  # ambiente + projeto + bindings prontos?
scripts/gate-local.sh                 # todos os gates locais (espelham ci.yml)
scripts/backup-point.sh               # bookmark Time Travel + evidências
scripts/deploy.sh                     # build → migrate → deploy → check (serializado)
scripts/postdeploy.sh                 # health + admin + migrate --check
scripts/retro.sh                      # run record + validação skill viva
```

Variáveis de ambiente (ver `references/pipeline-detail.md`): `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `EMDASH_TARGET_FINGERPRINT`, `EMDASH_DEPLOY_URL`, `EMDASH_D1_NAME`, `EMDASH_CICD_E2E`, `EMDASH_CICD_R2_BACKUP`.
