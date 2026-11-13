# EmDash — Documento de Instalação Integral (Deploy Completo)

**Escopo:** instalação completa do EmDash na Cloudflare — CMS + sandbox de plugins + stack de Registry self-hosted + stack de publicação delegada + ferramentas operacionais. O código está pronto; este documento organiza a ordem de instalação, os comandos e os pontos que exigem decisão/ajuste antes do deploy.

**Fonte:** inventário de implantação do repositório `emdash-main` (auditoria de 28 configurações Wrangler e 21 scripts de deploy), **verificado contra o código-fonte upstream público** ([github.com/emdash-cms/emdash](https://github.com/emdash-cms/emdash)) e a [documentação oficial da Cloudflare para EmDash](https://developers.cloudflare.com/workers/framework-guides/web-apps/emdash/). Nenhum deploy real foi executado — este documento é o roteiro de execução.

**Verificações feitas no código upstream (branch `main`):** `templates/starter-cloudflare/wrangler.jsonc`, `apps/aggregator/wrangler.jsonc`, `docs/src/content/docs/deployment/cloudflare.mdx`, `docs/src/content/docs/deployment/plugin-sandbox.mdx`, `docs/src/content/docs/plugins/registry.mdx`, `docs/src/content/docs/deployment/core-migrations.mdx`, `docs/src/content/docs/guides/backups.mdx`, além da [documentação Cloudflare para EmDash](https://developers.cloudflare.com/workers/framework-guides/web-apps/emdash/). O conteúdo confere com a auditoria; detalhes confirmados são marcados como **[verificado no código]**.

---

## 0. Pré-requisitos (resolver ANTES de instalar)

### 0.1 Infraestrutura e contas

| # | Pré-requisito | Por quê |
|---:|---|---|
| 1 | Conta Cloudflare dedicada à empresa | Todos os Workers, D1, R2, Queues, DOs e Access ficam nela |
| 2 | **Plano Workers Paid** | Obrigatório para o Worker Loader (sandbox de plugins). Sem ele, plugins sandboxed e o Registry não funcionam |
| 3 | Node.js + pnpm + Wrangler CLI instalados | Build e deploy de todos os apps |
| 4 | Domínio próprio ativo na MESMA conta Cloudflare | Workers, registry, catálogo e release-service precisam de rotas/domínios próprios |
| 5 | Conta/org GitHub com permissão de OIDC trust | Stack de publicação delegada (release-service) |
| 6 | Identidade AT Protocol / PDS (para publishers) | Requisito do release-service para contas de publicadores |

### 0.2 Bloqueadores a resolver antes do deploy (não estão no repositório)

| # | Bloqueador | Impacto | Ação |
|---:|---|---|---|
| B1 | Worker `blob-proxy` **não existe** no repositório | `apps/labeler` tem service binding `REGISTRY_BLOB_CACHE` apontando para ele | Implementar ou provisionar o blob-proxy antes de instalar o labeler |
| B2 | CDN Cumulus (`https://cdn.em-da.sh`) fixado em `packages/registry-lexicons/src/index.ts` | Registry self-hosted depende dele para assets | Decidir: apontar para o CDN upstream ou substituir por CDN próprio |
| B3 | Divergência de hostname do aggregator: `api.emdashcms.com` (runbook do labeler) vs `registry.emdashcms.com` (loader/docs/tests) | Contrato de rota inconsistente | Definir o hostname oficial do aggregator ANTES de implantar; não escolher por inferência |
| B4 | IDs hard-coded do upstream em várias configs | Contaminação de conta se deploy sem limpeza | Ver seção 7 (limpeza obrigatória) |
| B5 | Domínio do site CMS não definido | Sem rota própria, primeiro deploy cai em `workers.dev` | Definir o domínio e variável de ambiente no template |
| B6 | Verifier não suporta raiz Sigstore privada para GitHub interno/privado | Verificação falha em vez de aceitar confiança mais fraca | Validar política de repositórios GitHub antes de escolher a stack de release |

### 0.3 Decisões de configuração a registrar antes de começar

- Nome de produção do Worker do CMS (substituir `my-emdash-site`)
- Nome de produção do bucket R2 de mídia (substituir `my-emdash-media`)
- Hostnames: site CMS, aggregator (resolver B3), plugins-site, release-service
- Provider de email (Cloudflare Email Sending com domínio remetente verificado, ou SMTP externo) — necessário para magic links/invites/recovery

---

## 0-A. Critérios de seleção: o que entra e o que fica de fora, e por quê **[verificado no código]**

Esta secção fundamenta tecnicamente cada decisão de inclusão/exclusão, com base na documentação de deployment do próprio repositório (`docs/src/content/docs/deployment/cloudflare.mdx`, `plugin-sandbox.mdx`, `plugins/registry.mdx`, `guides/backups.mdx`) e nas configs Wrangler.

### Critério 1 — A unidade de instalação é UM Worker construído a partir de UM template

A documentação oficial é explícita: os templates Cloudflare já incluem **o entry point completo do Worker, os bindings nomeados de D1/R2 e o Durable Object de coedição**. O CMS não é um conjunto de serviços — pacotes `emdash`, `@emdash-cms/cloudflare`, admin UI e plugins são **compilados/incorporados ao build desse Worker único**. Por isso:

- **Entra:** exatamente o que o template `starter-cloudflare` declara (D1, R2, DO, cron) + o que o adapter injeta no build (`SESSION` KV, `IMAGES`, `ASSETS`).
- **Fica de fora:** qualquer recurso que só aparece em *outras* configs do monorepo (demos, fixtures, ferramentas `infra/*`). A existência de um `wrangler.jsonc` num pacote **não** significa que ele faz parte da instalação — o repositório tem 28 configs, mas a instalação base usa 1.

**Por que o starter e não blog/marketing/portfolio:** são alternativas mutuamente exclusivas para o *mesmo* Worker. A documentação de cada template é de site, não de serviço. Implantar os quatro em paralelo criaria quatro CMS independentes sem necessidade.

### Critério 2 — Cada binding do baseline tem uma função obrigatória no runtime

| Binding | Por que é obrigatório | O que acontece sem ele |
|---|---|---|
| `DB` (D1) | Banco canônico: conteúdo, usuários, settings. O adapter `d1()` o encontra **por nome** — `DB`/`MEDIA`/`LOADER` devem casar exatamente entre `wrangler.jsonc` e `astro.config.mjs` | Nenhum CMS |
| `MEDIA` (R2) | Mídia do CMS via adapter `r2()` | Sem uploads |
| `EMDASH_ROOMS` (DO) | Salas de coedição (`EmDashRoom`, storage SQLite). **Coedição está desligada por padrão**, mas a documentação manda manter binding + exports no baseline | Sem o binding, o editor cai em **single-editor mode com edit locks** (cada sessão entra nesse modo após 3 conexões falhadas). Não é erro, é degradação silenciosa |
| Cron `* * * * *` | Publicação programada + tarefas de manutenção/plugins/backups. A documentação é categórica: entradas agendadas só são publicadas pelo handler `scheduled` **e** exigem o Cron Trigger — **se qualquer um dos dois faltar, entradas agendadas nunca publicam**. Um cron que funciona local (timer do `astro dev`) **não** valida a config de produção | Entradas agendadas não saem do ar. Validar com `pnpm emdash doctor` (check `scheduler wiring`) |
| `IMAGES` | Transformações de mídia. **Não se declara manualmente**: o `@astrojs/cloudflare` injeta no config gerado quando o image service runtime é `cloudflare-binding` (default do template) | Na rota interna, imagens são servidas no **tamanho original** (sem erro, sem log); via URL de bucket, **500**. Verificar o binding real em `.wrangler/deploy/config.json` após o build |
| `SESSION` (KV) / `ASSETS` | Sessions do Astro e frontend/admin estáticos — ambos adicionados pelo adapter no build | Sem sessões / sem assets |

**Nota técnica do `exports`:** o campo `exports` (usado para declarar `EmDashRoom`) **não pode ser combinado** com um array `migrations` no mesmo `wrangler.jsonc`. Se o projeto já tiver migrations Wrangler próprias, declarar `EmDashRoom` em `migrations` (`new_sqlite_classes`) e o binding à parte. Os apps aggregator/labeler usam exatamente esse padrão.

### Critério 3 — Recursos opcionais entram só por decisão de feature, nunca "por precaução"

A documentação define com precisão o gatilho de cada extensão. Regra: **nada é criado porque aparece em outra config do monorepo** — cada recurso adicional tem um requisito funcional explícito:

| Recurso | Gatilho de inclusão (da doc oficial) | Estado no baseline |
|---|---|---|
| Worker Loader `LOADER` + `sandbox()` | Só se houver plugins `sandboxed`, Registry ou Marketplace. A doc diz literalmente: *"If the site does not use marketplace, registry, or sandboxed plugins, omit `sandboxRunner` and the `LOADER` binding"* | Fase 2 (decisão de produto) |
| KV `CACHE` (object cache) | Só quando se decidir cachear query results entre requisições; banco continua fonte da verdade | Desligado |
| `cacheCloudflare()` (route cache) | Cache HTML de rotas públicas, após políticas que excluam admin/API/variantes autenticadas | Desligado |
| AI Search / Vectorize | Pesquisa semântica (plugin `@emdash-cms/plugin-ai-search` substitui o antigo `aiSearch` — não instalar ambos) | Desligado |
| Email Sending | Magic links/invites/recovery. Sem provider de email, esses fluxos ficam **indisponíveis** (não degradam) | Condicional à política de auth |
| Cloudflare Access | Substituir auth nativa/passkey — alternativa, não requisito | Desligado |
| Hyperdrive/PostgreSQL | Alternativa ao D1. Plugins sandboxed são **D1-only** (o bridge fala direto com o binding `DB`) — Hyperdrive não satisfaz esse caminho | Não instalar com D1 |
| Stream, Cloudflare Images (provider), R2 público | Requisito de vídeo / gestão de mídia via conta Images / URL pública de bucket | Desligado / privado |

### Critério 4 — Serviços do ecossistema só entram como stack atômico

- **Registry:** a doc oficial de plugins diz que o EmDash usa o **registry hosted upstream** (`https://registry.emdashcms.com`) por padrão quando o sandbox está habilitado, e que o catálogo Registry só aparece no admin **depois** do sandbox runner configurado. Ou seja: para *consumir* plugins, **nenhum** serviço adicional é necessário. Self-hostar o registry é uma decisão de controlar o catálogo — e nesse caso aggregator + labeler + plugins-site são um stack único (o labeler tem service binding para o aggregator; o plugins-site aponta para o aggregator). Não existe "instalar metade".
- **Release delegada:** serviço classificado como **experimental** pelo próprio README; só para publicação delegada de plugins com GitHub OIDC + Access + AT Protocol.
- **Marketplace legado:** a doc de migração diz para mantê-lo apenas enquanto existirem plugins legados que verificam updates; descoberta nova vai pelo Registry. Instalação nova: fora.

### Critério 5 — Exclusão por tipo, não por qualidade

Os 21 arquivos Wrangler fora do baseline dividem-se em: demos públicas, playgrounds, fixtures de teste (E2E/perf), ferramentas de mantenedores (i18n, flue-review, discord-bot), documentação upstream e configs com **IDs hard-coded do ambiente upstream** (`infra/blog-demo`, `infra/cache-demo` — D1 UUID e account ID fixos). Nenhum deles é dependência do CMS; vários são inseguros de aplicar numa conta corporativa sem limpeza.

---

## 0-B. Fundamentação da ordem de instalação **[verificado no código]**

A ordem não é arbitrária — cada fase é pré-requisito funcional da seguinte, e dentro de cada fase a sequência segue o comportamento documentado do runtime.

### Por que o CMS vem primeiro

1. É o único bloco **autocontido**: um Worker + D1 + R2 + DO + cron, sem dependência de nenhum outro app do repositório.
2. O comportamento documentado do primeiro deploy: com o modo de migration `auto` (default), o EmDash aplica migrations core pendentes **na primeira requisição** ao Worker deployado, e responde **503 até que migrations grandes sejam aplicadas** via CLI. Ou seja, o deploy inicial já é "quase funcional" — o pipeline corporativo usa `emdash migrate` antes do deploy para que código novo não receba tráfego com schema antigo.
3. O seed de conteúdo é aplicado **uma única vez na primeira requisição** (lido de `.emdash/seed.json`, `package.json#emdash.seed` ou `seed/seed.json`); deploys seguintes contra banco existente não tocam no conteúdo.
4. O setup wizard é urgente e sequencial: **a primeira pessoa a completá-lo vira administrador**; passkeys ficam vinculadas ao hostname onde foram criadas. Por isso a ordem interna é: provisionar D1 (capturar UUID) → build → migrate → deploy → setup no domínio final (ou com `EMDASH_SITE_URL` já definido).

### Por que o domínio vem depois do primeiro deploy

A doc oficial determina: o primeiro deploy recebe URL `workers.dev`; o domínio customizado deve já estar ativo na mesma conta; **só depois** de o Worker responder com sucesso no `workers.dev` é que se adiciona a rota `custom_domain: true` e se faz deploy de novo. Manter o `workers.dev` ativo durante o teste de DNS distingue problema de roteamento de problema de aplicação. E o domínio deve estar resolvido **antes do setup wizard**, por causa da vinculação dos passkeys ao hostname.

### Por que o sandbox vem depois do CMS e antes do Registry

A doc de sandbox define a cadeia exata: `sandboxRunner` seleciona o runner **e habilita o catálogo do registry hosted**. Sem runner: plugins `sandboxed: []` não carregam; installs do marketplace/registry falham com `SANDBOX_NOT_AVAILABLE`; **o resto do site funciona normalmente**. Isso torna o sandbox um acréscimo seguro e não-bloqueante — pode ser ativado a qualquer momento depois, com rebuild + redeploy. A ordem CMS → sandbox → registry consumidor é a menor caminho até "instalar plugins do catálogo", sem nenhum serviço adicional.

Detalhe de implementação que fundamenta o passo: `sandbox()` valida o `wrangler.jsonc` **em tempo de build** — sem `worker_loaders`/`LOADER`, ele deixa o runner unset e loga aviso em vez de falhar. E com environments nomeados, **bindings não são herdados**: repetir `LOADER` em cada `env.<name>` que roda plugins sandboxed (e setar `CLOUDFLARE_ENV` no build para o Vite plugin e o `sandbox()` lerem o mesmo environment).

### Por que o registry self-hosted vem depois (e é opcional)

O CMS já consome o registry hosted por padrão. Self-hostar só se justifica por exigência de controle do catálogo — e aí a ordem interna é imposta por service bindings reais:

```text
aggregator ──(service binding)──▶ labeler ◀──(registry loader / URL)── plugins-site
```

- **aggregator primeiro**: é o backend de ingestão/consulta; a rota de produção é anexada fora do Wrangler config (decisão B3).
- **labeler depois**: tem service binding para o aggregator e **requer os recursos D1/R2 provisionados antes das migrations** (o script `db:migrate` é do Wrangler, diferente do `emdash migrate` do CMS). Bloqueado pelo `blob-proxy` externo (B1).
- **plugins-site por último**: a UI aponta para o endpoint do aggregator — só faz sentido deploy quando o aggregator está operacional.
- O cron `*/5 * * * *` do aggregator é **liveness ping** do Records DO (durante outages do Jetstream o DO pode ser evitado; o cron o acorda e retoma do cursor persistido) — não é agendamento de tarefa, é resiliência.

### Por que a release delegada é independente e vem no fim

Não depende do registry nem do CMS (não usa D1). A única ordem interna imposta é o **release-verifier antes do release-service** (service binding `RELEASE_VERIFIER`; o verifier é privado, `workers_dev: false`, sem rota pública). A `release-action` é GitHub Action, não Worker — entra só quando o release-service estiver em uso.

### Por que migrations antes do deploy (e nunca em paralelo)

Três comportamentos documentados fundamentam a regra:

1. **Lock de migration no D1**: EmDash segura um lock enquanto aplica migrations (do CLI e do modo `auto` do runtime). Uma segunda execução espera até 10 s e **falha sem aplicar**. Por isso o CI usa concurrency group keyado por `account ID + database UUID` e `cancel-in-progress: false`.
2. **Forward-only**: migrations core não têm down; rollback do Worker não reverte schema. O recovery point correto é o **bookmark do Time Travel gravado antes da migration**.
3. **Emparelhamento artefato-manifest**: o build gera `.emdash/migrations.json` (versão exata, sequência, locale, executor); versões de schema/registry de migrations/fingerprints obsoletos são **rejeitados** contra o pacote EmDash instalado. Reconstruir entre migration e deploy quebra o pareamento.

### Por que backup é etapa da instalação, não "depois"

A doc de backups define o que cada mecanismo **não** cobre: o export JSON do EmDash **não tem comando de restore** (é ferramenta de inspeção/export); o Time Travel **não** restaura mídia R2 nem a `EMDASH_ENCRYPTION_KEY`; a lista de rotação da encryption key **não** está no banco nem no bucket. Um recovery point completo = bookmark Time Travel (ou dump SQL offsite) + sync dos objetos R2 + lista de rotação da chave em secret manager — os três criados juntos e guardados fora da conta de produção.

## 1. FASE 1 — CMS base (Worker do site)

**Fonte:** `templates/starter-cloudflare` (template neutro; usar UM template — não implantar os quatro em paralelo).

### 1.1 Criar o projeto (método oficial) **[verificado no código]**

```bash
# Interativo — escolher: Cloudflare Workers / Starter / instalar deps / sandboxed plugins: No
npm create emdash@latest -- my-emdash-site

# Ou sem prompts:
npm create emdash@latest -- my-emdash-site --template cloudflare:starter --yes

cd my-emdash-site
```

**Importante:** o scaffolder gera um `EMDASH_ENCRYPTION_KEY` no `.env` — não commitar esse arquivo (o template já o inclui no `.gitignore`).

**Alternativa:** copiar `templates/starter-cloudflare` diretamente do repositório (estrutura idêntica ao que o scaffolder gera).

### 1.2 Ajustar o template

1. Substituir o nome do Worker (`my-emdash-site`) e do banco/bucket pelo identificador de produção.
2. Definir o domínio/rota. Ordem documentada: primeiro deploy em `workers.dev` → confirmar que o Worker responde → **só então** adicionar a rota e fazer deploy de novo:

```jsonc
// wrangler.jsonc — domínio customizado (após o Worker responder no workers.dev)
{ "routes": [{ "pattern": "www.example.com", "custom_domain": true }] }
```

3. Se email for requisito: onboard do domínio remetente e binding `EMAIL` + plugin `cloudflareEmail()` — ou configurar SMTP externo.
4. Validar o wiring do scheduler antes do deploy: `pnpm emdash doctor` (check `scheduler wiring` — confirma Cron Trigger + handler `scheduled` nos arquivos locais).

### 1.3 Provisionar recursos e capturar IDs

```bash
# D1 de produção (o UUID impresso deve ser guardado no estado da infraestrutura)
npx wrangler d1 create my-site-production
```

Em seguida, adicionar o `database_id` retornado ao binding `DB` no `wrangler.jsonc` **[verificado no código]**. Provisionar o **R2** de mídia (privado por padrão; NÃO expor o prefixo `backups/`).

> **Nota:** o primeiro `wrangler deploy` sem IDs explícitos auto-provisiona D1, R2 e o namespace KV. Isso é aceitável para um primeiro teste, mas em produção corporativa provisionar explicitamente e guardar os IDs — sem isso não há estado de infraestrutura reproduzível.

### 1.4 Sequência de build, migrations e deploy **[verificado no código]**

O pipeline correto (a ordem importa — não reconstruir entre migration e deploy):

```bash
# 1. Build — gera .emdash/migrations.json (versão, sequência, locale, executor)
pnpm build

# 2. Inspecionar o destino — em D1 o comando exige alvo explícito:
#    --wrangler-config wrangler.jsonc (ou --d1 <uuid-ou-nome>)
export CLOUDFLARE_ACCOUNT_ID="..."
export CLOUDFLARE_API_TOKEN="..."   # token com D1 Edit
pnpm emdash migrate --status --wrangler-config wrangler.jsonc

# 3. Aplicar migrations core (interativo pede confirmação; CI usa fingerprint)
pnpm emdash migrate --wrangler-config wrangler.jsonc

# 4. Deploy do MESMO artefato construído
pnpm wrangler deploy

# 5. Verificar (exit non-zero se houver migrations pendentes/desconhecidas)
pnpm emdash migrate --check --wrangler-config wrangler.jsonc
```

**Regras de migrations [verificado no código]:**
- `emdash migrate` **nunca cria banco faltante** — provisionar o D1 antes (seção 1.3).
- Migrations core são **forward-only**; execução interrompida pode deixar resultado ambíguo.
- **NÃO** substituir por `wrangler d1 migrations apply` — o executor oficial é `emdash migrate`.
- O EmDash mantém um **lock de migration no D1**: uma segunda execução simultânea espera até 10 s e falha sem aplicar. Serializar jobs por `account ID + database UUID` (usar concurrency group no CI: `emdash-migrations-${ACCOUNT_ID}-${D1_DATABASE_ID}`).
- Non-interativo (`--expected-target-fingerprint`) e todo apply com `--json` exigem o fingerprint impresso pelo `--status` após revisão local.
- Manter o manifest `.emdash/migrations.json` junto ao artefato de build (não commitar — está no `.gitignore` do template).

### 1.5 Setup do admin (primeiro acesso) **[verificado no código]**

```bash
# Preview local (opcional)
pnpm wrangler dev
# abrir /_emdash/admin/ no URL local
```

Após o deploy, abrir `/_emdash/admin/` no URL do Worker. **A primeira pessoa a concluir o wizard vira administrador** — completar o setup imediatamente após o deploy.

- **Passkeys só funcionam no hostname onde foram criados.** Com domínio próprio, rodar o setup nesse domínio, ou definir `EMDASH_SITE_URL` para o domínio ANTES do setup.
- Subir a chave de criptografia como secret para plugin settings encriptados:

```bash
npx wrangler secret put EMDASH_ENCRYPTION_KEY
```

### 1.6 Recursos instalados nesta fase

| Recurso | Binding/Nome | Quantidade |
|---|---|---:|
| Worker | site EmDash (entry `src/worker.ts`) | 1 |
| D1 | `DB` | 1 |
| R2 | `MEDIA` | 1 |
| Workers KV | `SESSION` — sessions do Astro, **adicionado pelo `@astrojs/cloudflare` no build** **[verificado no código]** | 1 namespace |
| Durable Object SQLite | `EmDashRoom` / `EMDASH_ROOMS` (storage `sqlite`, exportado em `exports`) | 1 classe |
| Cron Trigger | `* * * * *` (publicação programada + manutenção/plugins/backups) | 1 |
| Binding Images | `IMAGES` (injetado pelo adapter; validar em `.wrangler/deploy/config.json` após build) | 1 |
| Workers Static Assets | `ASSETS` — frontend + admin buildados, adicionado pelo adapter no build **[verificado no código]** | 1 |
| Domínio/rota | próprio (senão `workers.dev`) | 1 |
| Secret | `EMDASH_ENCRYPTION_KEY` — necessário antes de guardar plugin settings secretos | 1 |

**Config Wrangler do template [verificado no código]:** `compatibility_date: 2026-02-24` + `compatibility_flags: ["nodejs_compat"]` — manter a flag `nodejs_compat` a menos que atualize o compatibility date para `2026-08-04` ou posterior (a partir daí o Node.js compat vem por padrão). Os nomes dos bindings em `wrangler.jsonc` e `astro.config.mjs` devem coincidir.

---

## 2. FASE 2 — Sandbox de plugins (libera plugins sandboxed + Registry)

Sem esta fase, plugins `sandboxed`, Registry e Marketplace não carregam/instalam. Plugins sandboxed rodam em isolados separados (Dynamic Workers) **sem acesso a variáveis de ambiente nem filesystem**.

**Passos exatos [verificado no código]:**

1. Confirmar plano **Workers Paid** ativo (Dynamic Workers só existem no plano pago).

2. Em `wrangler.jsonc`, descomentar o `worker_loaders` (vem comentado no template):

```jsonc
{
  "worker_loaders": [
    { "binding": "LOADER" }
  ]
}
```

3. Em `astro.config.mjs`, importar `sandbox` e passar como `sandboxRunner`:

```js
import { d1, r2, sandbox } from "@emdash-cms/cloudflare";

emdash({
  database: d1({ binding: "DB", session: "auto", coalesce: true }),
  storage: r2({ binding: "MEDIA" }),
  sandboxRunner: sandbox(),
});
```

4. Rebuild e redeploy do Worker do CMS.

---

## 3. FASE 3 — Stack do Registry self-hosted (3 apps, ordem obrigatória)

**Pré-condição:** Fase 2 concluída + bloqueadores B1, B2 e B3 resolvidos.

Estes três apps são um **stack único** — não instalar parcialmente. Os apps aggregator e labeler têm migrations SQL próprias aplicadas pelos scripts Wrangler `db:migrate` (diferente do CMS, que usa `emdash migrate`).

### 3.1 Ordem de instalação

```text
1. apps/aggregator    (primeiro — backend de ingestão/consulta)
2. apps/labeler       (requer aggregator no ar + Access + blob-proxy)
3. apps/plugins-site  (UI pública; aponta para o aggregator próprio)
```

### 3.2 `apps/aggregator` — backend do registry

**Recursos [verificado no código — `apps/aggregator/wrangler.jsonc`]:**
- 1 Worker `emdash-aggregator` (entry `src/index.ts`, `nodejs_compat`, `compatibility_date 2026-02-24`)
- 1 D1 binding `DB` / database `emdash-aggregator`, `migrations_dir: ./migrations` (`database_id` **intencionalmente omitido** — wrangler auto-provisiona no primeiro deploy; para produção corporativa, provisionar antes e fixar o UUID)
- 4 queues: `emdash-aggregator-records`, `emdash-aggregator-records-dlq`, `emdash-aggregator-backfill`, `emdash-aggregator-backfill-dlq` (consumers com `max_batch_size`/`max_retries`/DLQ configurados)
- 2 DO classes com migrations próprias no Wrangler (`v1`: `RecordsJetstreamDO`, `v2`: `LabelIngestDO` — bindings `RECORDS_DO`, `LABEL_INGEST_DO`)
- Cron `*/5 * * * *` (liveness ping do Records DO durante outages do Jetstream)
- Secrets obrigatórios: `ADMIN_TOKEN`, `RECONCILIATION_TOKEN` (declarados em `secrets.required` — o deploy valida que estão setados; guard `requireAdminAuth` falha fechado com 503 se vazios)
- Vars de ambiente: `JETSTREAM_URL` (`wss://jetstream2.us-east.bsky.network/subscribe`), `RELAY_URL` (`https://bsky.network`), `IDENTITY_RESOLVER_URL` (`https://slingshot.microcosm.blue`), `LISTING_POLICY_MODE`, `LISTING_ALLOWLIST`, `LISTING_MODERATION_POLICY` — **sobrescrever `JETSTREAM_URL`/`RELAY_URL` para relays self-hosted se aplicável**
- `observability.enabled: true`

**Nota:** o config diz que as rotas de produção são anexadas no deploy e que o CDN (`cdn.emdashcms.com`) é um Worker separado a adicionar depois — confirmar com o bloqueador B2.

**Passos:**
1. Provisionar D1, queues, DOs (guardar IDs no estado) e fixar `database_id` no config.
2. Definir a rota de produção (NÃO está no wrangler.jsonc — é anexada fora do config).
3. `pnpm build` + aplicar migrations via script `db:migrate`.
4. `wrangler deploy` (valida os secrets `required`).
5. `wrangler secret put ADMIN_TOKEN` e `RECONCILIATION_TOKEN`.
6. Se usar environments nomeados, **repetir o bloco `secrets.required` em cada `env.<name>`** (não é herdado).

### 3.3 `apps/labeler` — moderação e labels

**Recursos:**
- 1 Worker
- 1 D1 `emdash-labeler` (migrations `0001`–`0011`)
- 3 R2 buckets: `emdash-labeler-media-quarantine`, `emdash-labeler-eval-datasets`, `emdash-labeler-eval-artifacts`
- 1 queue + 1 DLQ
- 2 DO classes: `LabelSubscriptionDO`, `LabelerDiscoveryDO`
- 2 Workflows: `emdash-labeler-assessment`, `emdash-labeler-live-evaluation`
- Workers AI binding `AI` + Images binding `IMAGES`
- Cron `*/5 * * * *`
- 4 secrets + Access app/policies

**Passos:**
1. Provisionar todos os recursos acima ANTES das migrations.
2. Configurar Access app/policies.
3. Resolver o service binding `REGISTRY_BLOB_CACHE` → Worker `blob-proxy` (bloqueador B1).
4. `pnpm build` + `db:migrate` + `wrangler deploy`.

**Dependência externa de dados (não é recurso Cloudflare):** endpoints AT Protocol/Bluesky — Jetstream, relay `bsky.network`, resolver `slingshot.microcosm.blue`.

### 3.4 `apps/plugins-site` — UI pública do catálogo

**Recursos:** 1 Worker com static assets + Workers Cache; domínio de catálogo próprio.

**Ajustes obrigatórios antes do deploy:**
1. `wrangler.jsonc` tem `account_id` fixo do upstream (`1f74638c495bc9f0330ce5c8e64c1b6b`) — **remover/substituir**.
2. `astro.config.mjs` fixa `site: https://plugins.emdashcms.com` — substituir pelo domínio próprio.
3. `src/lib/registry.ts` usa `DEFAULT_REGISTRY_URL` do `@emdash-cms/registry-loader` — parametrizar para o aggregator próprio (hostname decidido no bloqueador B3).

**Deploy:** `pnpm build && wrangler deploy` (script `deploy` do package).

---

## 4. FASE 4 — Stack de publicação delegada de plugins (experimental)

**Aviso:** o README do `apps/release-service` classifica o serviço como **experimental**. Validar o bloqueador B6 (política de repositórios GitHub / Sigstore) antes de implantar.

### 4.1 Ordem de instalação

```text
1. apps/release-verifier   (primeiro — Worker privado, sem rota pública)
2. apps/release-service    (consome o verifier via service binding)
3. apps/release-action     (GitHub Action, não é Worker)
```

### 4.2 `apps/release-verifier`

- 1 Worker **privado** (`workers_dev: false`), sem rota pública, sem bindings próprios.
- Consumido exclusivamente via service binding.
- Deploy: `vite build && wrangler deploy`.

### 4.3 `apps/release-service`

**Recursos:**
- 1 Worker público + static assets
- 5 DO classes: `IdentityDirectory`, `Approver`, `OAuthState`, `ServiceControl`, `Publisher`
- 3 Workflows
- 3 R2 buckets privados: `publication-staging`, `provenance`, `operations`
- 1 Analytics Engine dataset
- Service binding `RELEASE_VERIFIER`
- Secrets: `OAUTH_ASSERTION_KEYSET`, `ENCRYPTION_KEYRING`
- Access applications/audiences
- **Não usa D1.**

**Ajustes obrigatórios:**
1. `ACCESS_TEAM_DOMAIN` e Access audience IDs do ambiente de referência no Wrangler → substituir pelos da conta da empresa.
2. Configurar GitHub OIDC trust + domínios próprios + contas/PDS AT Protocol dos publishers.

**Deploy:** `vite build && wrangler deploy` (após o verifier existir).

### 4.4 `apps/release-action`

- GitHub Action empacotada — instalar/integrar no GitHub Actions somente quando usar o release-service.
- Requer permissão `id-token: write` nos workflows do publisher.

---

## 5. FASE 5 — Ferramentas operacionais

### 5.1 `infra/perf-monitor` (condicional)

- 1 D1, 1 queue + DLQ, 6 service bindings, cron e **6 probes auxiliares** gerados pelo Vite no build.
- **Atenção:** o README diz 4 probes mas a config gera 6 — reconciliar antes de implantar.
- Deploy: `pnpm build && pnpm deploy:probes && wrangler deploy`.

### 5.2 Marketplace legado (`packages/marketplace`) — só migração

- **NÃO instalar em instância nova.** Manter temporariamente apenas se existirem plugins legados instalados que precisam verificar/baixar updates (descoberta nova migra para o Registry).
- O wrangler.jsonc contém UUID D1 do upstream hard-coded (`e07c5b3b-c3e0-4cec-be3b-1ae0bb87da35`) — remover/substituir se usado.

---

## 6. Fora da instalação (não implantar)

Demos (`demos/cloudflare`, `demos/playground`, `demos/preview`), documentação upstream (`docs/wrangler.jsonc`), i18n dashboard, fixtures de teste (`e2e/fixture-cloudflare`, `fixtures/perf-site`), demos de infra com IDs upstream (`infra/blog-demo`, `infra/cache-demo`), discord-bot, do-demo/do-solo-demo, flue-review, playground de blocos, harness de verificação (`packages/registry-verification`), sweep de avaliação do labeler.

**Também não criar sem decisão explícita de feature:** Queues/Workflows para o CMS base, segundo D1/R2, KV `CACHE`, Vectorize, Workers AI no CMS, AI Search, Cloudflare Access no CMS, Stream, Hyperdrive/PostgreSQL (alternativa ao D1; plugins sandboxed são D1-only), adapter SQL em Durable Objects.

---

## 7. Limpeza obrigatória de IDs do upstream (checklist)

| Arquivo | O que remover/substituir |
|---|---|
| `apps/plugins-site/wrangler.jsonc` | `account_id` upstream (`1f74638c495bc9f0330ce5c8e64c1b6b`) |
| `packages/blocks/playground/wrangler.jsonc` | `account_id` upstream (fora da instalação, mas revisar se copiado) |
| `infra/blog-demo`, `infra/cache-demo` | D1 UUID, R2/KV e account ID upstream (não aplicar) |
| `packages/marketplace/wrangler.jsonc` | UUID D1 upstream |
| `apps/release-service/wrangler.jsonc` | `ACCESS_TEAM_DOMAIN` + Access audience IDs |
| `apps/labeler/docs/runbooks.md` vs loader/docs | hostname aggregator divergente (B3) |
| `packages/registry-lexicons/src/index.ts` | `REGISTRY_CUMULUS_ORIGIN = https://cdn.em-da.sh` (B2) |
| `apps/plugins-site/astro.config.mjs` | `site: https://plugins.emdashcms.com` |

**Regra geral:** nenhum hostname, account ID, audience ID, D1/KV UUID ou domínio do ambiente upstream entra na conta da empresa.

---

## 8. Tabela de secrets por app

| App | Secrets | Observação |
|---|---|---|
| CMS (starter) | `EMDASH_ENCRYPTION_KEY` | Antes de guardar plugin settings secretos |
| aggregator | `ADMIN_TOKEN`, `RECONCILIATION_TOKEN` | — |
| labeler | 4 secrets (ver runbook) | + credenciais Access |
| release-service | `OAUTH_ASSERTION_KEYSET`, `ENCRYPTION_KEYRING` | + Access/OIDC |
| discord-bot (fora) | credenciais Discord/GitHub | não instalar |

**Política:** secrets em GitHub Environment/secret manager; somente nomes e requisitos nos manifests. Nunca valores de tokens em artefatos ou logs.

---

## 9. Ordem de execução resumida (MVP do deploy completo)

```text
[0] Pré-requisitos: conta CF + Workers Paid + domínio + pnpm/wrangler
[0] Resolver B1–B6 (blob-proxy, Cumulus, hostname aggregator, domínio site, política GitHub)

FASE 1 — CMS
  1.1 npm create emdash@latest --template cloudflare:starter (guardar EMDASH_ENCRYPTION_KEY do .env)
  1.2 renomear Worker/banco/bucket, definir domínio
  1.3 wrangler d1 create → fixar database_id no wrangler.jsonc
  1.4 build → emdash migrate --status → migrate → wrangler deploy → migrate --check
  1.5 abrir /_emdash/admin/ e completar o setup (1º usuário = admin) + secret EMDASH_ENCRYPTION_KEY

FASE 2 — Sandbox
  2.1 Workers Paid confirmado
  2.2 descomentar worker_loaders/LOADER no wrangler.jsonc + sandboxRunner: sandbox() no astro.config
  2.3 rebuild + redeploy do CMS

FASE 3 — Registry (stack único)
  3.1 aggregator: recursos → rota → db:migrate → deploy → secrets
  3.2 labeler: recursos + Access + blob-proxy → db:migrate → deploy
  3.3 plugins-site: limpar account_id/domínio/registry URL → build → deploy

FASE 4 — Release (experimental)
  4.1 release-verifier → deploy (privado)
  4.2 release-service: Access/OIDC/domínios → deploy
  4.3 release-action no GitHub Actions

FASE 5 — Ops
  5.1 perf-monitor (reconciliar 4 vs 6 probes)
  5.2 marketplace legado: apenas se migração de instalação existente
```

---

## 10. Verificação pós-deploy

1. `emdash migrate --check` no CMS.
2. Health/readiness checks por Worker.
3. Verificação dos service bindings: labeler→aggregator, plugins-site→aggregator, release-service→release-verifier.
4. Verificação de domínios/rotas de todos os apps.
5. Migrations check de aggregator e labeler.
6. Backup (comandos oficiais da doc de backups) **[verificado no código]**:

```bash
# Recovery point do D1 — gravar o bookmark ANTES de qualquer migration
npx wrangler d1 time-travel info my-database   # guardar a saída completa com o deploy

# Retenção: 7 dias (Workers Free) / 30 dias (Workers Paid). Janela maior → dump SQL offsite.

# Restore (para de escrever no site antes; sobrescreve o banco in place e cancela queries em voo)
npx wrangler d1 time-travel restore my-database --bookmark="<pre-migration-bookmark>"

# Backup dos objetos R2 (credenciais read-only; guardar FORA da conta de produção)
aws s3 sync s3://emdash-media ./emdash-media-backup \
  --endpoint-url https://<account-id>.r2.cloudflarestorage.com

# Restore de mídia → SEMPRE em bucket de recovery vazio, nunca por cima do bucket em produção
aws s3 sync ./emdash-media-backup s3://emdash-media-recovery \
  --endpoint-url https://<account-id>.r2.cloudflarestorage.com
```

Limitações documentadas de cada mecanismo:
- O **JSON export** do EmDash não tem comando de restore (admin, API ou CLI) — não usar como recovery point; ele omite usuários/auth, plugin data/secrets, mídia e comentários.
- O **Time Travel** restaura conteúdo/usuários/settings/plugin data/migration records, mas **não** restaura mídia R2 nem a `EMDASH_ENCRYPTION_KEY` — restaurar artefato, mídia e chaves antes de reabrir tráfego.
- A **lista de rotação da `EMDASH_ENCRYPTION_KEY`** não está no banco nem no bucket — backup em secret manager, separado.
- Dump SQL offsite: `wrangler d1 export --remote` falha com tabelas virtuais FTS5 (índice de busca) — exportar tabelas por nome (4 arquivos: schema/folders/data/indexes, nessa ordem na importação) e checar statements >100 KB (`awk 'length($0) >= 100000'`).
- Se o bucket tiver domínio público/CDN: restringir a origem a objetos de mídia — a rota de mídia do EmDash recusa `backups/`, mas uma origem pública de bucket expõe **todo** objeto por URL.
7. Rollback: o rollback do Worker sozinho **não** reverte migrations — versionar artefato de build e configuração usada na migration.

---

## 11. Workflow de CI oficial para deploy do CMS com migrations **[verificado no código]**

Secrets/variáveis no GitHub: `CLOUDFLARE_API_TOKEN` (secret, token com D1 Edit), `CLOUDFLARE_ACCOUNT_ID`, `D1_DATABASE_ID`, `EMDASH_TARGET_FINGERPRINT` (variáveis). Concurrency keyada pelos dois identificadores imutáveis do D1:

```yaml
name: Deploy
on:
  workflow_dispatch:

concurrency:
  group: emdash-migrations-${{ vars.CLOUDFLARE_ACCOUNT_ID }}-${{ vars.D1_DATABASE_ID }}
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
      - name: Inspect EmDash migration target
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
        run: |
          pnpm emdash migrate --status --json \
            --account-id "${{ vars.CLOUDFLARE_ACCOUNT_ID }}" \
            --d1 "${{ vars.D1_DATABASE_ID }}"
      - name: Apply EmDash migrations
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          EMDASH_TARGET_FINGERPRINT: ${{ vars.EMDASH_TARGET_FINGERPRINT }}
        run: |
          pnpm emdash migrate \
            --account-id "${{ vars.CLOUDFLARE_ACCOUNT_ID }}" \
            --d1 "${{ vars.D1_DATABASE_ID }}" \
            --expected-target-fingerprint "$EMDASH_TARGET_FINGERPRINT"
      - run: pnpm wrangler deploy
      - name: Check EmDash migrations
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
        run: |
          pnpm emdash migrate --check \
            --account-id "${{ vars.CLOUDFLARE_ACCOUNT_ID }}" \
            --d1 "${{ vars.D1_DATABASE_ID }}"
```

Atualizar `EMDASH_TARGET_FINGERPRINT` somente após revisar o alvo alterado localmente — o fingerprint não contém credencial, mas trocá-lo sem revisar remove a proteção contra migrar o banco errado.

---

## 12. Resumo de recursos totais (instalação integral)

| Tipo | Quantidade | Detalhe |
|---|---:|---|
| Workers | 7 + probes | CMS, aggregator, labeler, plugins-site, release-verifier, release-service, perf-monitor (+ probes e blob-proxy externo) |
| D1 | 4 | CMS, aggregator, labeler, perf-monitor |
| R2 | 7 | mídia CMS (1) + 3 do labeler + 3 privados do release-service |
| KV | 1 | `SESSION` do CMS (auto-provisionada no primeiro deploy) |
| Durable Objects | 10 classes | EmDashRoom + 2 aggregator + 2 labeler + 5 release-service |
| Queues | 8 | 4 aggregator + 2 labeler (1 queue + 1 DLQ) + 2 perf-monitor (1 queue + 1 DLQ) |
| Workflows | 5 | 2 labeler + 3 release-service |
| Cron Triggers | 3 | CMS (`* * * * *`), aggregator (`*/5`), labeler (`*/5`) + perf-monitor |
| GitHub Action | 1 | release-action |

---

## 13. Fontes

**Repositório upstream (código lido diretamente):**
- https://github.com/emdash-cms/emdash — repositório oficial (MIT, 1.0 estável)
- https://raw.githubusercontent.com/emdash-cms/emdash/main/templates/starter-cloudflare/wrangler.jsonc — config do template CMS
- https://raw.githubusercontent.com/emdash-cms/emdash/main/apps/aggregator/wrangler.jsonc — config do aggregator
- https://raw.githubusercontent.com/emdash-cms/emdash/main/docs/src/content/docs/deployment/cloudflare.mdx — ordem de deploy, bindings e rationale, entry point, cron, imagens, domínios
- https://raw.githubusercontent.com/emdash-cms/emdash/main/docs/src/content/docs/deployment/plugin-sandbox.mdx — requisitos do sandbox (Workers Paid, LOADER, PluginBridge, SANDBOX_NOT_AVAILABLE)
- https://raw.githubusercontent.com/emdash-cms/emdash/main/docs/src/content/docs/plugins/registry.mdx — registry hosted por padrão, fluxo de instalação de plugins
- https://raw.githubusercontent.com/emdash-cms/emdash/main/docs/src/content/docs/deployment/core-migrations.mdx — workflow oficial de migrations e CI
- https://raw.githubusercontent.com/emdash-cms/emdash/main/docs/src/content/docs/guides/backups.mdx — Time Travel, dump D1 offsite, backup R2, limitações do JSON export

**Documentação oficial Cloudflare:**
- https://developers.cloudflare.com/workers/framework-guides/web-apps/emdash/ — criação, bindings (`DB`, `MEDIA`, `SESSION`, `IMAGES`, `ASSETS`, `LOADER`), deploy, setup do admin, sandbox

**Anúncios de produto (contexto):**
- https://blog.cloudflare.com/emdash-wordpress/ — anúncio do beta
- https://blog.cloudflare.com/emdash-cms-plugin-registry/ — EmDash 1.0 e o registry descentralizado de plugins

**Auditoria local fornecida:**
- `EMDASH-DEPLOYMENT-AUDIT.md` + `audit_emdash_inventory.py` (28 configs Wrangler, 21 scripts de deploy, classificação BASE/condicional/fora)
