# EmDash — Estudo: Registro de Entidades, Grafo, Workflows e Portal MCP como plugins

**Princípio reitor (a regra do usuário):** o mínimo de código próprio possível. Tudo aqui é **customização e costura sobre o código EmDash já deployado na Cloudflare** — nada reimplementa a plataforma, nada contraria os templates de plugin existentes. As referências fortes são o próprio repositório upstream (`emdash-cms/emdash`), seus plugins oficiais (`webhook-notifier`, `audit-log`, `forms`, `marketplace-test`) e os 230 plugins do registry público (`plugins.emdashcms.com`).

**Fontes primárias lidas:** skill `creating-plugins` (formato, capacidades, hooks, storage, rotas/MCP, admin UI, testes) e suas 12 referências; skill `emdash-cli` (schema/migrations/content); tutorial oficial "Your first sandboxed plugin"; docs de plugins (registry, installing, registry-client); código dos plugins oficiais no clone local.

---

## 1. O que a plataforma JÁ dá (mapa "não construir")

Antes de qualquer plugin, o levantamento abaixo mostra que boa parte do requisito já existe no EmDash — o trabalho próprio é modelagem + costura, não infraestrutura:

| Requisito do usuário | O que o EmDash já tem (upstream) | Código próprio necessário |
|---|---|---|
| Cadastro de tipos de entidade (pessoas, PJ, agentes, máquinas, objetos, sensores, apps, processos, workflows) | **Content collections com schema builder visual** — criar tipos é administração/seed, não código (`emdash schema create/add-field` via CLI, ou admin). Campos tipados, labels, required | **Zero** — modelo de dados é seed |
| Identidade estável por entidade | Todo entry tem **ID estável** (formato `01…` ULID-like) + slug + revisões + histórico | Zero |
| Endereçabilidade | REST API autenticada (`/_emdash/api/...`), CLI remoto, MCP embutido; conteúdo consultável por coleção/ID | Zero |
| Permissões | **RBAC nativo** (Administrator/Editor/Author/Contributor) + **API tokens com escopos** (ex.: `mcp:tools:<pluginId>`, `transfer:export`…) | Zero (mapeamento no plugin 3) |
| Responsabilidades / auditoria | **Plugin oficial `audit-log`** rastreia create/update/delete com ator; hooks expõem `actor: {id, role}` em todo save autenticado | Zero — instalar o plugin oficial |
| Registro dispara ação externa | **Plugin oficial `webhook-notifier`** — POST em URLs configuradas quando conteúdo/mídia muda, com proteção SSRF | Referência de implementação |
| Processos reutilizáveis / versionados | **Revisões e drafts nativos** de qualquer collection — uma "definição de workflow" é um entry versionado | Modelagem |
| Execução agendada | Hook `cron` de plugin + handler `scheduled` do Worker | Costura |
| Exposição via MCP com auth | **Servidor MCP embutido no core** (`packages/core/src/mcp`) + **MCP tools declaráveis por plugin** (Zod, permission, consent, escopo `mcp:tools`) | Declaração, não servidor |
| Catálogo de plugins | Registry hosted (instalação com consent dialog, verificação de checksum/provenance) | Zero |

**Conclusão da tabela:** nenhum componente exige novo serviço Cloudflare, novo banco ou novo runtime. Tudo roda no Worker CMS já planejado (Documento de Instalação, Fases 1–2), como **plugins sandboxed** — o formato que a própria plataforma recomenda por padrão ("Use a sandboxed plugin unless…").

---

## 2. Decisão de arquitetura: um grafo único ou grafos individuais?

### Recomendação: UM grafo lógico único, materializado sobre o armazenamento existente — não um banco de grafos separado, não grafos por domínio.

**Por que não um banco de grafos separado (Neo4j, etc.):**
1. O EmDash roda sobre D1/SQLite — a plataforma não prevê outro banco no Worker CMS; adicionar um serviço externo de grafos violaria a regra do mínimo código próprio e a regra de "não brigar com a plataforma".
2. A escala deste domínio (registro de entidades de uma empresa: pessoas, apps, sensores, processos — ordens de grandeza de 10³–10⁶ nós) é trivial para consultas SQL indexadas; a potência de um grafo nativo (traversal recursivo massivo) não é necessária no dia 1.
3. O admin, o CLI, o MCP, o RBAC e o audit-log já operam sobre collections — um grafo externo ficaria fora de todo o governável.

**Por que UM grafo e não grafos individuais por tipo de entidade:**
1. **As relações atravessam tipos por natureza**: `pessoa —trabalha-para→ empresa`, `app —deployado-em→ máquina`, `sensor —acoplado-a→ objeto`, `agente —autorizado-por→ pessoa`. Grafos separados por tipo obrigariam a duplicar o modelo de arestas e quebrariam exatamente as consultas que importam (quem/what está conectado a quem/what).
2. **Permissões e auditoria uniformes**: um único padrão de aresta (`sujeito → predicado → objeto`) significa uma única regra de governança, um único lugar para checar permissão de escrita, um único log.
3. **O predicado vira vocabulário controlado** — e o EmDash tem **taxonomias nativas** para isso: os tipos de relação são termos de uma taxonomia `relations`, administráveis no admin, zero código.
4. **Quando grafos separados seriam a resposta certa** (registrar a exceção): se no futuro um domínio tiver ciclo de vida/trust radicalmente distinto (ex.: telemetria efêmera de sensores em volume alto vs. cadastro legal imutável), a separação correta é por **collection/índice**, não por banco — o que o modelo abaixo já permite (edges filtráveis por predicado e por tipo de nó).

### Modelo do grafo (costura sobre storage de plugin)

```text
NÓS    = entries em collections existentes (person, legal-entity, agent, machine,
         object, sensor, app, process, workflow) — criadas via schema builder/seed
ARESTAS = records na storage collection "edges" do plugin entity-graph:
         { id, fromId, fromType, predicate, toId, toType, since, until?, actor, note }
PREDICADOS = termos da taxonomia "relations" (owns, works-for, deployed-on,
         attached-to, authorized-by, part-of, triggers, ...)
```

Consultas de vizinhança (1–2 hops) resolvem com índices; traversals longos (raros no cadastro) resolvem por iteração no hook/rota com limite de profundidade — suficiente para o domínio de registro.

---

## 3. Identidade estável, endereçável, com permissões e responsabilidades

Quatro camadas, todas já existentes na plataforma, costuradas pelo plugin de identidade:

| Camada | Mecanismo EmDash | Exemplo |
|---|---|---|
| **Identidade do registro** | Entry ID estável da collection (ULID-like) + slug | `01ABC…` em `apps` |
| **Endereçamento** | URL da API/CLI/MCP: `content get apps <id>`; rota pública do plugin se quiser URI pública | `/_emdash/api/content/apps/01ABC…` |
| **Permissões (o que a identidade pode fazer)** | **API token com escopos** gerado por admin e registrado no entity — o plugin guarda o mapeamento `entityId ↔ tokenId/scopes` (nunca o segredo) | sensor com token `content:read` só da collection `telemetry` |
| **Responsabilidades (o que a identidade responde por)** | Grafo: arestas `responsible-for`/`authorized-by` + **actor snapshot** em todo hook autenticado + plugin oficial `audit-log` | deploy do app X executado pelo agent Y às 14:03 |

**Regra de costura importante:** o plugin NUNCA armazena segredo de token — o EmDash já é o detentor dos tokens; o plugin registra apenas o vínculo e consulta `users:read`/admin para validar. A criptografia de settings do plugin (`ctx.settings` com segredos encriptados + `EMDASH_ENCRYPTION_KEY`) cobre o que for inevitável guardar.

---

## 4. "O ato do registro dispara um workflow"

### Design: definições são conteúdo, instâncias são storage, gatilhos são hooks — zero motor de workflow próprio

```text
REGISTRO (novo entry numa collection de entidade)
   │ hook content:afterSave { isNew: true, collection, actor }
   ▼
[plugin registry-workflows]
   1. consulta definições (entries da collection "workflows") que casam
      (collection-alvo + evento "on-create") e estão ativas
   2. cria INSTÂNCIA na storage collection "runs" { workflowId, entityId,
      status: pending, attempts: 0 }
   3. executa PASSOS da definição, cada um usando uma capability existente:
      ├─ email      → ctx com capability email:send (transport já configurado)
      ├─ webhook    → ctx.http.fetch (capability network:request + allowedHosts)
      │               → dispara deploy (CI), assina contrato (API externa), etc.
      ├─ content    → ctx.content.create (capability content:write)
      │               → cria entidade derivada (ex.: entry "contrato" a partir do cadastro)
      └─ graph      → arestas no entity-graph (plugin 1) — ex.: estabelece
                      "app X —managed-by→ equipe Y"
   4. falhas ficam registradas em runs com status/attempts; o hook cron do
      plugin reprocessa com backoff (o cron do CMS já roda * * * * *)
```

**Os três exemplos do usuário, mapeados sem código novo de infraestrutura:**

| Exemplo do usuário | Definição (entry em `workflows`) | Passos |
|---|---|---|
| Cadastro de cliente dispara email | `on-create: clients` | email para o cliente + email para o comercial (capability `email:send`) |
| Cadastro de app dispara deploy | `on-create: apps` | webhook para o pipeline (CI/CD da skill `emdash-cicd`) via `network:request` com host permitido |
| Cadastro estabelece contrato | `on-create: clients` | `content:write` cria entry em `contracts` (com campos do cliente) + aresta `client —has-contract→ contract` |

**Referências fortes (não ir contra):**
- `webhook-notifier` oficial: padrão de SSRF-safe outbound HTTP em eventos de conteúdo — copiar o padrão de validação de URL/host, não reimplementar por fora;
- `audit-log` oficial: padrão de registro de ator/evento;
- tutorial "Your first sandboxed plugin" (save-log): o esqueleto exato de hook + storage + rota.

**Limites aceitos conscientemente (versus um motor de workflow genérico):** passos sequenciais simples, sem DAG/paralelismo/branching complexo no v1 — se um dia precisar, o passo é um webhook para um orquestrador externo (a skill emdash-cicd já é o orquestrador de deploy). Isso mantém o plugin pequeno, auditável e dentro das capacidades sandboxed.

---

## 5. Portal MCP de capacidades

**O que já existe:** o EmDash já roda um servidor MCP no core, e plugins sandboxed **declaram MCP tools** que são registradas nesse servidor — com Zod input schema, permissão de rota explícita, consentimento do administrador na instalação, ativação separada pós-install, e escopo de token `mcp:tools` ou `mcp:tools:<pluginId>`. Um caller precisa da permissão da rota E do escopo MCP — auth dupla já resolvida pela plataforma.

**O que o "Portal" adiciona (costura, não servidor novo):**
1. Cada plugin do suite expõe suas capacidades como MCP tools declaradas (abaixo).
2. Um admin page (Block Kit, declarativo) lista todas as capacidades expostas, seus escopos e estado (consentido/ativo) — o "portal" é uma **vista de governança**, não um novo endpoint.
3. Alinhamento com a direção Cloudflare (auth de agentes): quando a Cloudflare publicar o formato definitivo de portal/agents card, a costura é frente a Access/tokens — sem tocar no core, porque o servidor MCP é do EmDash e os tools são dos plugins.

**Regra:** NÃO subir um segundo servidor MCP paralelo — isso brigaria com a plataforma. O portal vive dentro do MCP existente.

---

## 6. O suite de plugins (3 plugins, formato que estabelece o padrão)

Todos **sandboxed**, scaffolded por `pnpm dlx @emdash-cms/plugin-cli init <nome>` (o CLI gera manifest, testes, workspace, skills — exatamente o formato upstream), distribuíveis pelo registry da empresa quando este existir, ou instalados via `sandboxed: []` no `astro.config.mjs`.

### Plugin 1 — `entity-graph` (grafo + identidade)

| Aspecto | Design |
|---|---|
| **Storage (manifest)** | `edges` com índices `fromId`, `toId`, `predicate`, `[fromType,predicate]`, `[toType,predicate]`; uniqueIndexes `id` |
| **Hooks** | `content:afterDelete` → limpa arestas órfãs (integridade referencial do grafo) |
| **Rotas (privadas)** | `edges/query` (vizinhança por nó/predicado, limite de profundidade), `edges/put`, `edges/delete` (permission própria) |
| **MCP tools** | `graphNeighbors` (consulta), `linkEntities` (escrita, `destructive:false`), `unlinkEntities` (`destructive:true`) |
| **Capabilities** | `content:read` (resolver nós), `taxonomies:read` (predicados) |
| **Admin (Block Kit)** | Página "Grafo": busca de entidade → vizinhança; widget de estatísticas (nós por tipo, arestas por predicado) |
| **Zero-código associado** | Predicados = taxonomia `relations` (admin); tipos de nó = collections (schema builder) |
| **Estimativa** | ~1–2 semanas (a maior parte é admin UI e testes) |

### Plugin 2 — `registry-workflows` (registro dispara processo)

| Aspecto | Design |
|---|---|
| **Storage** | `runs` com índices `workflowId`, `entityId`, `status`, `createdAt`; `steps` com índices `runId`, `status` |
| **Hooks** | `content:afterSave` (gatilho `isNew`), `cron` (reprocesso com backoff) |
| **Rotas** | `workflows/instantiate` (disparo manual — permission própria), `runs/list`, `runs/retry` |
| **MCP tools** | `triggerWorkflow` (permite a um agente disparar processo por MCP), `getRunStatus` |
| **Capabilities** | `content:read` (definições), `email:send`, `network:request` (+allowedHosts por setting), `content:write` (passos que criam entidades) |
| **Admin** | Página "Runs" com status/attemptos/erro; página de definições linkando para a collection `workflows` |
| **Referência obrigatória** | `webhook-notifier` (SSRF), `audit-log` (ator) |
| **Estimativa** | ~2–3 semanas |

### Plugin 3 — `capability-portal` (identidade/credenciais + portal MCP)

| Aspecto | Design |
|---|---|
| **Função** | Mapear `entityId ↔ tokenId/escopos` (registro do vínculo; segredo fica no EmDash), listar capacidades MCP do suite, expor ferramentas de busca de identidade |
| **Storage** | `credentials` com índices `entityId`, `tokenId` (uniqueIndex), `scopes` |
| **Hooks** | `content:afterDelete` → marca credencial como revogada (a revogação real do token é do EmDash — o plugin só espelha) |
| **Rotas/MCP** | `whois` (rota privada + MCP tool: resolve entidade → tipo, vínculos, credenciais, responsabilidades via grafo) — a ferramenta canônica do portal |
| **Capabilities** | `users:read` |
| **Admin** | Página "Portal": tabela de capacidades expostas (plugin, tool, escopo, consentimento, ativo) + busca whois |
| **Estimativa** | ~1 semana |

### O padrão de plugins da empresa (derivado do formato upstream — este é o formato a adotar)

Todo plugin da empresa segue exatamente o formato que o `plugin-cli` gera e que os plugins oficiais usam — o padrão É o formato da plataforma, acrescido de convenções internas:

1. **Manifesto `emdash-plugin.jsonc` é o contrato de confiança** — toda capability, rota pública, storage e MCP tool declarada lá; nada além do declarado.
2. **Sandboxed por padrão**; native só com justificativa escrita (perde registry/consent).
3. **Storage declarada com índices explícitos**; estados voláteis em `ctx.kv`; configuração em `ctx.settings` (segredos encriptados).
4. **Toda rota privada com permission explícita**; pública só com consent renovado.
5. **MCP tool sempre com Zod schema**; operações destrutivas marcadas `destructive: true`.
6. **Testes com `createPluginTestHost()`** (transporte) e `createPluginRuntimeTestHost()` (boundary real) — o mesmo padrão dos plugins oficiais; `pnpm run validate && typecheck && test && build` como gate.
7. **Revisões adversariais** (skill `adversarial-reviewer`) em todo release — o pipeline `emdash-cicd` já orquestra.
8. **Skills embarcadas**: o scaffold gera `skills/creating-plugins` no projeto do plugin — mantê-las sincronizadas via `upgrade-emdash`.
9. **Versionamento semântico + CHANGELOG** por plugin (mesma disciplina da skill viva `emdash-cicd`).

---

## 7. Sequência de implementação (do zero código ao suite completo)

| Passo | Trabalho | Código próprio | Quando |
|---|---|---|---|
| 1 | Fases 1–2 do Documento de Instalação (CMS + sandbox ativo no Workers Paid) | — | Semana 1 (já planejado) |
| 2 | Instalar plugins oficiais `audit-log` e `webhook-notifier` do registry | Zero | Semana 1 |
| 3 | Criar collections de entidade (person, legal-entity, agent, machine, object, sensor, app, process, workflow) + taxonomia `relations` via schema builder/seed | Zero (seed) | Semana 2 |
| 4 | Plugin `entity-graph` (scaffold → storage → rotas → MCP → admin → testes) | Pequeno | Semanas 2–3 |
| 5 | Plugin `registry-workflows` (definições seed → hooks → steps → runs → admin) | Médio | Semanas 4–6 |
| 6 | Plugin `capability-portal` (mapeamentos + whois + vista de capacidades) | Pequeno | Semana 7 |
| 7 | Registrar tudo no pipeline `emdash-cicd` (gates + review + retro) e publicar versões | — | Contínuo |

**Critérios de aceitação do suite (verificáveis):**
- Cadastro de um cliente novo → email recebido + entry em `contracts` criado + aresta no grafo (run record `status: completed`).
- Cadastro de um app novo → webhook entregue ao pipeline de deploy (payload auditado, host na allowlist).
- `whois` via MCP (token com `mcp:tools:capability-portal`) retorna identidade, vínculos e responsabilidades da entidade.
- Aresta removida via MCP exige `destructive:true` e aparece no audit-log com ator.
- Todos os plugins passam `validate/typecheck/test/build` + review adversarial sem findings Critical/High.

---

## 8. Referências (todas upstream — usar como fonte forte, não contrariar)

**Repositório e skill de plugins:**
- `skills/creating-plugins/SKILL.md` + referências (`hooks.md`, `storage.md`, `api-routes.md`, `admin-ui.md`, `sandbox-boundaries.md`, `content.md`) — a fonte canônica do formato
- Tutorial: [Your first sandboxed plugin](https://github.com/emdash-cms/emdash/blob/main/docs/src/content/docs/plugins/creating-plugins/your-first-plugin.mdx)
- [Plugin CLI](https://github.com/emdash-cms/emdash) — `pnpm dlx @emdash-cms/plugin-cli init`

**Plugins oficiais (padrões de implementação):**
- `packages/plugins/webhook-notifier` — outbound HTTP seguro em eventos de conteúdo (base do plugin 2)
- `packages/plugins/audit-log` — rastreio de ator/evento (base de responsabilidades)
- `packages/plugins/forms`, `marketplace-test` (fixture maximal: tudo que o formato suporta)
- Catálogo público: [plugins.emdashcms.com](https://plugins.emdashcms.com/search) (230 plugins; verificar similares antes de escrever — ex.: SEO/Rank EmDash já expõe MCP tools; VePrompts cataloga MCP servers)

**Docs de produto:**
- [Registry](https://docs.emdashcms.com/plugins/registry/) — instalação com consent, verificação de release
- [Installing plugins](https://docs.emdashcms.com/plugins/installing/) — registro em `sandboxed: []`
- [Querying the registry](https://docs.emdashcms.com/plugins/registry-client/) — se a empresa quiser catálogo próprio dos seus plugins

**Documentos anteriores desta série:** `EMDASH-DEPLOYMENT-AUDIT.md` (auditoria), `EMDASH-INSTALACAO-INTEGRAL.md` (instalação), skill `emdash-cicd` (pipeline), `EMDASH-CONSIDERACOES-FINAIS.md` (custos/prazos/aceitação).
