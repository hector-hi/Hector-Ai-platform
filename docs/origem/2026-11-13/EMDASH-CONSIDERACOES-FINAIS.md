# EmDash — Considerações Finais: custos, prazos, aceitação e o que ainda falta decidir

**Posição na documentação:** este é o quarto documento da série (a série cresceu — ver o quinto abaixo). Relaciona-se aos demais:

1. `EMDASH-DEPLOYMENT-AUDIT.md` (fornecido) — inventário e auditoria de 28 configs Wrangler / 21 scripts de deploy
2. `EMDASH-INSTALACAO-INTEGRAL.md` — roteiro de instalação integral com critérios e ordem fundamentados
3. Skill `emdash-cicd` (pasta `emdash-cicd/`) — pipeline vivo de desenvolvimento, integração e deploy (6 scripts executáveis)
4. **Este documento** — custos, prazos, critérios de aceitação, riscos, monitoramento e decisões pendentes
5. `EMDASH-PLUGIN-SUITE-ESTUDO.md` — estudo do suite de plugins (registro de entidades, grafo, workflows, portal MCP)

---

## 1. Custos (preços oficiais Cloudflare, nov/2026)

### 1.1 Tabela de preços dos produtos usados pela instalação EmDash

| Produto | Uso no EmDash | Plano Free | Plano Paid (Workers Paid, $5/mês por conta) |
|---|---|---|---|
| Workers (runtime) | Todos os Workers | 100k req/dia; 10 ms CPU/req | **10 M req/mês + $0,30/M adicional**; 30 M CPU-ms/mês + $0,02/M adicional; sem cobrança de egresso |
| Dynamic Workers (sandbox) | Plugins sandboxed via `LOADER` | — | **$0,002 por Dynamic Worker** instanciado |
| D1 | CMS, aggregator, labeler, perf-monitor | 5 GB total; 5 M rows read/dia; 100k rows written/dia | **$0,75/GB-mês**; $0,001/M rows read; $1,00/M rows written |
| R2 | Mídia CMS, buckets labeler/release | 10 GB-mês; 1 M Class A/mês; 10 M Class B/mês | **$0,015/GB-mês**; Class A $4,50/M; Class B $0,36/M |
| Durable Objects (SQLite) | EmDashRoom, aggregator/labeler/release DOs | 100k req/dia; 13.000 GB-s/dia; 5 GB | Req $0,15/M; **duração $12,50/M GB-s** (128 MB alocados, hibernáveis não cobram); SQL rows read $0,001/M, written $1,00/M; 5 GB-mês + $0,20/GB |
| Workers KV | `SESSION` (CMS), cache opcional | 1 GB; 100k read/dia; 1k write/dia | $0,50/GB-mês; read $0,50/M; write $5,00/M |
| Queues | Registry (aggregator/labeler), perf-monitor | 10k ops/dia | **$0,40/M operations** |
| Workers AI | Labeler, flue-review | 10k Neurons/dia | $0,011/1.000 Neurons acima da franquia |
| Images (transformações) | `IMAGES` binding do CMS | **5.000 transformações únicas/mês** | cobradas como Images transformations; erro `9422` acima do limite (novas falham, cacheadas seguem servindo) |
| Workers for Platforms | Só se virar plataforma multi-site | — | $25/mês + uso |

Fontes: [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/), [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [preços agregados](https://www.cloudflare.com/plans/).

### 1.2 Cenários de custo mensal estimado

| Cenário | Componentes | Estimativa |
|---|---|---|
| **MVP — só CMS** (site institucional de baixo tráfego) | $5 base + D1 <5 GB + R2 <10 GB + KV sessões + <5k transformações | **~$5–8/mês** |
| CMS em produção real (~1 M req/mês, 20 GB mídia) | $5 + R2 20 GB ($0,30) + D1 ~2 GB ($1,50) + transformações | **~$10–20/mês** |
| CMS + sandbox de plugins ativo | + Dynamic Workers ($0,002/instância — instância por plugin carregado, escala a zero) | + centavos a poucos dólares |
| **+ Registry self-hosted** (aggregator+labeler+plugins-site) | + Queues, 2 DOs adicionais, D1/R2 extra, Workers AI do labeler | **+ $10–30/mês** em tráfego moderado |
| **+ Release delegada** (verifier+service) | + 5 DOs, 3 Workflows (steps: 500k/mês incl., $0,80/100k extra), Analytics Engine | + ~$5–15/mês |
| Instalação integral (tudo) | — | **~$30–70/mês** em tráfego moderado |

### 1.3 Alertas de custo específicos desta instalação

1. **DO de duração é o maior alavanca de custo.** O `RecordsJetstreamDO` do aggregator mantém WebSocket ao Jetstream aberto — DO com WebSocket pode hibernar (não cobrado), mas DO ativo em memória sem hibernar cobra $12,50/M GB-s (128 MB fixos por DO). O exemplo oficial: 100 DOs ativos 8 h/dia = **$142,95/mês**. Monitorar duração de DO desde o primeiro dia do registry.
2. **Transformações de imagem** são cobradas por combinação única (imagem×parâmetros) por mês: 500 imagens × 2 tamanhos = 1.000 transformações. Acima de 5.000/mês, novas transformações retornam erro `9422` — o site continua no ar, imagens novas saem sem variante.
3. **KV write é o item mais caro por unidade** ($5/M) — sessões do Astro usam KV; tráfego autenticado alto move esse número.
4. **Workflows** passou a cobrar steps (500k/mês incluídos, depois $0,80/100k) — relevante para labeler (2 workflows) e release-service (3).
5. **Budget alerts**: a Cloudflare agora permite ver uso faturável e criar alertas de orçamento direto nas páginas de produto (Workers, D1, R2, KV, Queues, DO) — **criar alerta no primeiro dia**.
6. **Uma assinatura Workers Paid cobre a conta toda** — os 7 Workers da instalação integral dividem as franquias de 10 M req e 30 M CPU-ms; CPU, não request count, costuma estourar primeiro.

---

## 2. Prazos (estimativas por fase, com dependências)

Pressuposto: 1–2 pessoas técnicas com domínio de Cloudflare/Astro. Datas em dias úteis a partir da decisão de go.

| Fase | Trabalho | Estimativa | Dependência crítica |
|---|---|---|---|
| **0. Decisões e conta** | Conta CF dedicada, Workers Paid, domínio, B1–B6 | 2–5 dias (paralelizável) | Domínio na conta; decisão B3 (hostname) |
| **1. CMS** | Criar projeto, provisionar D1/R2, migrate, deploy, setup admin, domínio | **1–2 dias** | Nenhuma externa — autocontido |
| **2. Sandbox** | LOADER + sandboxRunner + redeploy | **2–4 horas** | Workers Paid ativo |
| **3. Registry self-hosted** | Aggregator → labeler → plugins-site + migrations + Access | **5–10 dias** | **B1 blob-proxy** (construir ~2–5 dias se decisão for self-host), B2 Cumulus, B3 hostname |
| **4. Release delegada** | Verifier → service → GitHub Action + Access/OIDC | **5–10 dias** | B6 (política GitHub/Sigstore); serviço **experimental** |
| **5. Ops** | Perf-monitor + probes | 1–2 dias | Reconciliar README (4) vs config (6 probes) |
| **Pipeline CI/CD** (skill emdash-cicd) | Instalar skill, conectar ao repo, primeiro run completo | 1–2 dias | Repositório da empresa criado |

**Caminho crítico realista para MVP:** Fase 0 + Fase 1 + Fase 2 = **~1 semana até um CMS em produção com plugins sandboxed funcionais** (consumindo o registry hosted upstream — sem precisar da Fase 3). A Fase 3 só entra no caminho se a exigência de controlar o catálogo for formal.

**Gargalos de prazo fora do código:** criação da conta corporativa com billing; verificação do domínio remetente (email); Access/OIDC com a equipe de identidade; contas AT Protocol/PDS para publishers (Fase 4).

---

## 3. Critérios de aceitação (definition of done por fase)

Formato: cada fase só é "aceita" quando TODOS os critérios verificáveis passam. Critérios de máquina = scripts da skill `emdash-cicd` (exit codes no `references/pipeline-detail.md`); critérios de agente = skills upstream; critérios humanos = revisão assistida.

### Fase 1 — CMS
| # | Critério | Como verificar |
|---|---|---|
| 1.1 | `preflight.sh` sem FAIL | exit 0 (avisos aceitáveis) |
| 1.2 | Gates verdes (format, lint, typecheck, unit, browser) | `gate-local.sh` exit 0 |
| 1.3 | `emdash doctor` com `scheduler wiring` passando | saída do doctor |
| 1.4 | Migrations aplicadas e verificadas | `emdash migrate --check` exit 0 |
| 1.5 | Deploy publicado e acessível | `postdeploy.sh` exit 0 (página + `/_emdash/admin/` + bindings no config gerado) |
| 1.6 | Setup wizard concluído no domínio final (ou `EMDASH_SITE_URL` definido antes) | 1º usuário é admin; passkey funciona no domínio de produção |
| 1.7 | Entrada agendada publicada no horário | criar post agendado +1 min; admin sem aviso "Scheduled publishing needs attention" |
| 1.8 | Bookmark Time Travel registrado | `backups/<ts>/time-travel.json` existe |
| 1.9 | Review adversarial sem findings Critical/High | skill `adversarial-reviewer` sobre o diff de configuração |

### Fase 2 — Sandbox
| # | Critério | Como verificar |
|---|---|---|
| 2.1 | `LOADER` no wrangler.jsonc (descomentado) + `sandboxRunner: sandbox()` no astro.config | `preflight.sh` PASS em LOADER |
| 2.2 | Plugin sandboxed de teste instala e executa do catálogo Registry | admin → Registry → Install; sem `SANDBOX_NOT_AVAILABLE` |
| 2.3 | Site permanece saudável com sandbox ativo | `postdeploy.sh` exit 0 |

### Fase 3 — Registry (stack único, aceitação integrada)
| # | Critério | Como verificar |
|---|---|---|
| 3.1 | Aggregator no ar com rota própria resolvida | health check da rota; migrations `0001`–`0014` aplicadas |
| 3.2 | Secrets `ADMIN_TOKEN`/`RECONCILIATION_TOKEN` setados (deploy valida `secrets.required`) | `wrangler deploy` não reclama de secret |
| 3.3 | Labeler conecta ao aggregator via service binding | sem erro de binding no tail; migrations `0001`–`0011` aplicadas |
| 3.4 | plugins-site aponta para o aggregator PRÓPRIO (sem account_id/domínio upstream) | grep no wrangler.jsonc/astro.config pós-limpeza |
| 3.5 | Fluxo ponta a ponta: publish → aggregator ingere → labeler modera → plugins-site lista | teste com plugin de teste em conta AT Protocol própria |
| 3.6 | Nenhum ID/domínio upstream remanescente | checklist seção 7 do doc de instalação |

### Fase 4 — Release (experimental)
| # | Critério | Como verificar |
|---|---|---|
| 4.1 | B6 resolvido (política GitHub/Sigstore validada) | decisão registrada por escrito |
| 4.2 | Verifier privado sem rota pública | `workers_dev: false`; chamado só via service binding |
| 4.3 | Release de teste ponta a ponta com provança verificada | release-action → release-service → verifier OK |
| 4.4 | Time aceita o risco "experimental" por escrito | registro de decisão |

### Classificação de aceitação UX (framework upstream)
Para jornadas de aceitação (`acceptance/journeys`), usar a taxonomia oficial do `ux-acceptance-coordinator`: **PASS / PASS_WITH_FRICTION / FAIL_PRODUCT / FAIL_INFRASTRUCTURE / INCONCLUSIVE** — resultado funcional reportado separado de achados de UX; a alegação do tester não é prova (coordinator verifica com checks independentes).

### Pipeline CI/CD (skill viva)
| # | Critério | Como verificar |
|---|---|---|
| P.1 | 6 scripts executam sem erro de sintaxe/uso | `bash -n` + dry runs |
| P.2 | Um run completo dev→retro gera run record | `runs/run-*.md` com estágios |
| P.3 | Todo gap declarado é incorporado antes do fim da sessão | `retro.sh` exit 0 (sem gaps pendentes) |
| P.4 | `version` do SKILL.md = última entrada do CHANGELOG | validação do `retro.sh` |

---

## 4. Riscos e mitigação (registro vivo)

| ID | Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|---|
| R1 | Custo de DO de duração no aggregator (WebSocket Jetstream) | Média | Alto ($100+/mês) | Validar hibernação do `RecordsJetstreamDO` antes de aceitar a Fase 3; budget alert |
| R2 | `blob-proxy`/Cumulus externos (B1/B2) travam o registry self-hosted | Alta | Médio | MVP consome registry hosted; Fase 3 só após construir/substituir ambos |
| R3 | Divergência de hostname aggregator (B3) quebra consumers | Média | Médio | Decisão única registrada antes do deploy; teste ponta a ponta 3.5 |
| R4 | Passkeys presos ao hostname errado (setup em workers.dev) | Média | Médio | Rodar setup no domínio final ou definir `EMDASH_SITE_URL` antes |
| R5 | Migration interrompida (forward-only) | Baixa | Alto | Bookmark antes de toda migration (exit 3 do deploy sem backup); CI serializado |
| R6 | Release-service experimental muda contrato | Média | Baixo (fase opcional) | Tratar Fase 4 como piloto; aceitar risco por escrito (4.4) |
| R7 | Transformações de imagem >5k/mês degradam mídia nova | Média | Médio | Monitorar usage; considerar plano Images pago se mídia crescer |
| R8 | Cron novo/alterado demora até 15 min para ativar | Certa | Baixo | Não é defeito: agendar deploys de mudança de cron fora de janelas de publicação |
| R9 | Skills upstream mudam (upgrade-emdash atualiza skills do projeto) | Média | Baixo | Protocolo Skill Viva item 4: refletir na execução seguinte |

---

## 5. Monitoramento e operação (mínimo desde o dia 1)

1. **Observability** — aggregator já nasce com `observability.enabled: true`; ativar para todos os Workers.
2. **Budget alerts** nas páginas de produto (novo recurso Cloudflare) — Workers, D1, R2, KV, Queues, DO.
3. **`wrangler tail`** para validar cron: cada run imprime `"* * * * *" @ ... - Ok`; publicações logam `[scheduled] Published N scheduled item(s)`.
4. **Dashboard do admin**: "Scheduled publishing needs attention" quando entrada passou do horário sem run em 5 min — usá-lo como canário de scheduler.
5. **Health checks pós-deploy** em toda release (`postdeploy.sh`) — página pública, admin, `migrate --check`.
6. **Run records** (`runs/`) como trilha de auditoria: estágios, exit codes, gaps → CHANGELOG.

---

## 6. Decisões pendentes (registro com dono e prazo)

| ID | Decisão | Afeta | Recomendação | Prazo sugerido |
|---|---|---|---|---|
| D1 | Domínio do site CMS | Fase 1 | Definir antes do setup wizard (passkeys) | Dia 1 |
| D2 | Provider de email (CF Email Sending vs SMTP) | Fase 1 (auth) | Decidir com política de email da empresa | Antes do setup |
| D3 | Ativar sandbox de plugins já no MVP? | Fase 2 | Sim, se houver qualquer intenção de plugins ($0,002/Dynamic Worker) | Junto com Fase 1 |
| D4 | Self-hostar registry ou consumir hosted? | Fase 3 | Consumir hosted no MVP; self-host só com requisito de controle de catálogo | Decisão de produto, semana 2 |
| D5 | Hostname oficial do aggregator (B3) | Fase 3 | `registry.<empresa>.com` (coerente com loader/docs) — validar com time | Antes da Fase 3 |
| D6 | Construir blob-proxy próprio ou depender do upstream? (B1) | Fase 3 | Construir (Worker simples de cache de blobs) se self-host | Antes da Fase 3 |
| D7 | CDN Cumulus: upstream vs próprio (B2) | Fase 3 | Upstream inicialmente; parametrizar `REGISTRY_CUMULUS_ORIGIN` | Antes da Fase 3 |
| D8 | Release delegada entra? (B6) | Fase 4 | Só com política GitHub validada; piloto experimental | Semana 3+ |
| D9 | Perf-monitor: 4 ou 6 probes? | Fase 5 | Reconciliar README vs config antes de implantar | Antes da Fase 5 |
| D10 | Staging: ambiente separado com D1/R2 próprios | Todas | Sim — Worker Previews não herdam bindings; nunca compartilhar preview com produção | Junto com Fase 1 |

---

## 7. O que ainda vale conhecer (além do que já está documentado)

1. **`emdash site export/import`** — transferência de site inteiro (content model, conteúdo, histórico, mídia; sem usuários/secrets) com plano revisado por digest sha256 — útil para migrar staging→produção e para disaster recovery parcial. Na skill `emdash-cli`.
2. **`upgrade-emdash`** — atualizador oficial que também **atualiza as skills do projeto** (`.agents/skills/`) e gera work order `.emdash/UPGRADE.md` — conectar isso ao protocolo Skill Viva (item 4: mudanças upstream refletem na skill na execução seguinte).
3. **Workers for Platforms ($25/mês)** — se a empresa evoluir de "um site EmDash" para "plataforma de sites para clientes" (o caminho que o próprio EmDash anuncia), este é o plano; os 7 Workers atuais não o exigem.
4. **EmDash Build** — construtor de sites por IA do mesmo org (alpha, para hosting providers); não faz parte da instalação, mas é o contexto de produto do ecossistema.
5. **MCP server embutido** — o EmDash expõe MCP para edição de conteúdo por agentes (humano E agente gerenciam o mesmo CMS); relevante para o pipeline de conteúdo (não de deploy).
6. **Quotas técnicas que podem morder**: CPU máx 30 s/invocação padrão (15 min em cron/queue consumer — o backfill do aggregator conta com isso); D1 rejeita statements ≥100.000 bytes (afeta dumps); subrequests 1.000 (Paid).
7. **Fonte única de verdade de preços**: [cloudflare.com/plans](https://www.cloudflare.com/plans/) e [developers.cloudflare.com/workers/platform/pricing](https://developers.cloudflare.com/workers/platform/pricing/) — re-verificar a cada trimestre (Workflows já mudou de preço em 2026).

---

## 8. Resumo executivo

- **Custo MVP (CMS + sandbox): ~$5–20/mês.** Instalação integral: ~$30–70/mês em tráfego moderado. O item a vigiar é duração de Durable Objects no registry.
- **Prazo MVP: ~1 semana** (fases 0–2). Registry self-hosted e release delegada são decisões de produto separadas, +1–2 semanas cada, condicionadas a B1/B2/B3/B6.
- **Aceitação é verificável por código**: os scripts da skill `emdash-cicd` (exit codes) + skills upstream (adversarial-reviewer, agent-browser, ux-acceptance) + taxonomia PASS/FAIL oficial. Nenhuma fase é aceita por opinião.
- **10 decisões pendentes** (D1–D10) com recomendação e prazo sugerido — D1, D2, D3 e D10 bloqueiam ou afetam a Fase 1 e devem sair no dia 1.

*Fontes de preço verificadas em 13/11/2026: [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [R2](https://developers.cloudflare.com/r2/pricing/), [Durable Objects](https://developers.cloudflare.com/durable-objects/platform/pricing/), [planos agregados](https://www.cloudflare.com/plans/), [Workflows billing](https://developers.cloudflare.com/changelog/20/), [budget alerts](https://developers.cloudflare.com/changelog/product/r2/). Demais fatos técnicos: repositório [emdash-cms/emdash](https://github.com/emdash-cms/emdash) e docs oficiais citadas nos documentos 1–3 desta série.*
