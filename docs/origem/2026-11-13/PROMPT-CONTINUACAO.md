# PROMPT DE CONTINUAÇÃO — Projeto EmDash na Cloudflare (entregar este texto à próxima IA)

Você está continuando um trabalho de planejamento e implantação do **EmDash CMS** (CMS open-source da Cloudflare, full-stack TypeScript sobre Astro, MIT, repositório `github.com/emdash-cms/emdash`) para uma instalação corporativa completa na Cloudflare. O trabalho anterior produziu uma série de documentos e uma skill executável. **Nada foi deployado ainda** — tudo está em fase de planejamento validado contra o código-fonte upstream real.

## 1. O que existe e onde (nesta ordem de leitura)

| # | Artefato | Conteúdo |
|---|---|---|
| 0 | `EMDASH-DEPLOYMENT-AUDIT.md` + `audit_emdash_inventory.py` (fornecidos pelo usuário) | Auditoria das 28 configs Wrangler e 21 scripts de deploy do repositório; classificação BASE/condicional/fora |
| 1 | `EMDASH-INSTALACAO-INTEGRAL.md` | Roteiro de instalação integral (5 fases): CMS → sandbox → registry self-hosted → release delegada → ops. Com critérios de seleção (seção 0-A) e fundamentação da ordem (seção 0-B), ambos verificados no código upstream |
| 2 | `emdash-cicd/` (skill viva, v1.1.0) | Pipeline dev→review→integration→backup→deploy→verify→retro com 6 scripts bash executáveis e protocolo Skill Viva (toda execução gera run record; gap não incorporado = falha; version↔CHANGELOG validado por `retro.sh`) |
| 3 | `EMDASH-CONSIDERACOES-FINAIS.md` | Custos oficiais (MVP ~$5–20/mês; integral ~$30–70/mês; alerta: DO de duração), prazos (MVP ~1 semana), critérios de aceitação por fase, riscos R1–R9, decisões pendentes D1–D10 |
| 4 | `EMDASH-PLUGIN-SUITE-ESTUDO.md` | Estudo do suite de plugins: registro de entidades, grafo, workflows disparados por cadastro, identidades com permissões, portal MCP |

**Repositório upstream clonado** (se seu ambiente não o tiver: `git clone --depth 1 https://github.com/emdash-cms/emdash.git`) — contém as skills oficiais em `skills/` e `.agents/skills/`, plugins oficiais em `packages/plugins/`, framework de aceitação em `acceptance/`.

## 2. Decisões já tomadas (não reabrir sem motivo novo)

1. **Unidade de instalação = 1 Worker** construído do template `starter-cloudflare`; D1 `DB` + R2 `MEDIA` + DO `EmDashRoom` + cron `* * * * *` + bindings injetados pelo adapter (`SESSION` KV, `IMAGES`, `ASSETS`).
2. **Grafo de entidades: UM grafo lógico único** sobre storage de plugin (arestas `from→predicado→to`, predicados = taxonomia nativa `relations`), NÃO banco de grafos separado, NÃO grafos por domínio.
3. **Workflows**: definições = content collection (versionada pelas revisões nativas); gatilho = hook sandboxed `content:afterSave` (`isNew`); instâncias = storage do plugin; passos = capabilities existentes (`email:send`, `network:request`, `content:write`); reprocesso = hook `cron`. Referência de implementação: plugin oficial `webhook-notifier` (SSRF-safe).
4. **MCP Portal**: NÃO construir segundo servidor MCP — o core EmDash já tem servidor MCP e plugins sandboxed declaram MCP tools (Zod, permission, consent, escopo `mcp:tools:<pluginId>`). O "portal" é uma vista de governança em admin page Block Kit.
5. **Suite = 3 plugins sandboxed**: `entity-graph`, `registry-workflows`, `capability-portal`, scaffolded por `pnpm dlx @emdash-cms/plugin-cli init`.
6. **Skill viva**: alterações em `emdash-cicd/` exigem bump de `version` + entrada em `CHANGELOG.md` (validado por `scripts/retro.sh`).

## 3. Regras invioláveis do usuário

- **Mínimo de código próprio possível** — tudo é customização/costura sobre o código EmDash existente.
- **Não ir contra a plataforma**: as skills oficiais do repositório prevalecem sobre qualquer coisa nossa; não reimplementar o que o EmDash já faz (schema builder, RBAC, tokens com escopo, revisões, taxonomias, audit-log, MCP).
- **Acompanhar os templates/plugins existentes** (registry com 230 plugins em plugins.emdashcms.com; oficiais: webhook-notifier, audit-log, forms, marketplace-test) como referência forte.
- Idioma dos entregáveis: **português**.

## 4. Correções já feitas na revisão final (para não reintroduzir)

- Contagens da instalação integral corrigidas: **R2 = 7** (1 CMS + 3 labeler + 3 release-service), **Queues = 8** (4 aggregator + 2 labeler + 2 perf-monitor).
- `gate-local.sh` agora **detecta os scripts do package.json** — site scaffolded só tem `typecheck` (astro check); `format:check`/`lint`/`test:*` são do monorepo/toolchain completa e aparecem como SKIP, não falha.
- Série de documentos renomeada para 5 itens (o doc de considerações dizia "quarto e último" antes do estudo de plugins existir).

## 5. Próximos passos (ordem)

1. **Semana 1**: decisões D1/D2/D3/D10 (domínio, email, sandbox, staging) → Fases 1–2 da instalação (`npm create emdash@latest --template cloudflare:starter`, `wrangler d1 create`, migrate, deploy, setup em `/_emdash/admin/`, LOADER+sandboxRunner). Instalar plugins oficiais `audit-log` e `webhook-notifier`.
2. **Semana 2**: collections de entidade (person, legal-entity, agent, machine, object, sensor, app, process, workflow) + taxonomia `relations` via schema builder/seed — **zero código**.
3. **Semanas 2–7**: os 3 plugins do suite, na ordem `entity-graph` → `registry-workflows` → `capability-portal`, cada um com testes (`createPluginTestHost()`/`createPluginRuntimeTestHost()`), review adversarial e gates do pipeline `emdash-cicd`.
4. Registry self-hosted e release delegada **só** se a decisão D4/D8 for por self-host (bloqueadores B1 blob-proxy e B2 Cumulus não estão no repositório).

## 6. Como verificar fatos (fontes de verdade)

- Código: `github.com/emdash-cms/emdash` (skills em `skills/` e `.agents/skills/`; docs em `docs/src/content/docs/`)
- Deploy: `developers.cloudflare.com/workers/framework-guides/web-apps/emdash/`
- Preços: `cloudflare.com/plans` + `developers.cloudflare.com/workers/platform/pricing/` (re-verificar a cada trimestre)
- Registry: `plugins.emdashcms.com` + `docs.emdashcms.com/plugins/registry/`
- Documentos desta série (acima) — tudo marcado **[verificado no código]** foi lido do upstream em 13/11/2026.

## 7. Estado atual resumido

- Nenhum recurso Cloudflare provisionado; nenhuma conta definida; domínio da empresa não fornecido (decisão D1).
- Todos os scripts da skill testados em sintaxe e comportamento (preflight contra o template real, retro com/sem gaps, colisão de timestamp).
- O que falta: execução real. O caminho crítico começa nas decisões D1–D10 do doc de considerações.

Ao continuar: leia os 5 documentos nesta ordem, clone o repositório upstream se necessário, siga a skill `emdash-cicd` (ela é o contrato do pipeline), e ao descobrir qualquer procedimento novo ou faltante, incorpore-o à skill (protocolo Skill Viva) e aos documentos — eles são vivos por design.
