# Para o agente que continua este trabalho

Este arquivo substitui o antigo `PROMPT-CONTINUACAO.md` (preservado em `docs/origem/2026-11-13/`). Ele vale para qualquer agente — Claude, ChatGPT/Codex, Perplexity, Cursor.

## O projeto em uma frase

Dar a uma pessoa a infraestrutura de uma empresa grande, usando o EmDash CMS na Cloudflare como substrato pronto e escrevendo de próprio apenas cola, costura e o que for genuinamente original.

## De quem é o projeto

O projeto é do Hector. Ele decide; o agente estuda, propõe, executa e relata. Decisões registradas em `docs/05-decisoes.md` não se reabrem sem fato novo. O que ainda não foi decidido se pergunta — não se presume.

## Regras que não se quebram

1. **Nunca infra, nunca substrato.** Não reimplementar o que o EmDash já entrega: schema builder, RBAC, tokens com escopo, revisões, taxonomias, audit-log, servidor MCP, sandbox de plugins, migrations, backups. A lista completa está em `docs/00-visao.md`.
2. **O upstream prevalece.** As skills oficiais do EmDash (`building-emdash-site`, `emdash-cli`, `creating-plugins`, `adversarial-reviewer`, `agent-browser`, `ux-acceptance-coordinator`, `upgrading-emdash`) mandam no domínio delas. Em conflito com qualquer texto nosso, vale o upstream e o conflito vira correção nossa.
3. **Fato se confere no código.** Antes de afirmar como o EmDash se comporta, ler o código ou a doc upstream — não confiar na memória nem em documento nosso antigo. A doc do EmDash também existe como servidor MCP em `https://docs.emdashcms.com/mcp`.
4. **Dizer o que foi verificado e o que não foi.** A documentação marca a origem de cada afirmação (ver a legenda em `docs/README.md`). Manter essa marcação.
5. **Tudo versionado.** Mudança em `docs/` entra em `docs/CHANGELOG.md`. Mudança em `skills/emdash-cicd/` exige bump de `version` no `SKILL.md` e entrada no `CHANGELOG.md` da skill — o `retro.sh` verifica.
6. **Segredo nunca em arquivo nem em conversa.** Tokens e chaves vivem em secrets do GitHub, secrets do Worker ou gerenciador de segredos.
7. **Português** em todos os entregáveis.

## Onde está cada coisa

- `docs/README.md` — índice, ordem de leitura e convenções.
- `docs/05-decisoes.md` — o que está decidido, o que está pendente e o que cada pendência bloqueia. **Ler antes de agir.**
- `skills/emdash-cicd/SKILL.md` — o contrato do pipeline.
- Código do EmDash — `github.com/emdash-cms/emdash`. Não está copiado aqui de propósito: é dependência, não código nosso.

## Estado em 13/11/2026

- **O repositório principal é o Cloudflare Artifacts** (`hector-ai/hector-ai-platform`, ramo `main`); o GitHub é espelho. Enviar com `skills/emdash-cicd/scripts/artifacts.sh push --to main --mirror origin`. O Workers Builds ainda não está conectado.
- Domínio definitivo: `hector-ai.space` (`EMDASH_SITE_URL` no `wrangler.jsonc`). A rota do domínio entra depois de o Worker responder no `workers.dev`.
- O site existe na raiz deste repositório (template `starter-cloudflare`, EmDash 1.5.0, sandbox ligado). Build, typecheck, `emdash doctor` e `wrangler deploy --dry-run` passam.
- Na Cloudflare existem o banco D1 `hector-ai-platform` e o bucket R2 `hector-ai-platform-media`. **O Worker ainda não foi publicado.**
- Os workflows `ci.yml` e `deploy.yml` existem. O deploy espera o Hector configurar no GitHub o secret `CLOUDFLARE_API_TOKEN` e a variável `CLOUDFLARE_ACCOUNT_ID`.
- `backup-point.sh`, `deploy.sh` e `postdeploy.sh` **nunca rodaram num deploy real**. O primeiro run vai achar coisas — incorporá-las é o protocolo, não um acidente.
- Caminho crítico: Hector confere o alvo (fingerprint) → `pipeline.sh deploy` → rota do domínio → setup do admin em `hector-ai.space` imediatamente → conectar o Workers Builds.

## Ao terminar uma sessão

Commitar no branch de trabalho, atualizar os changelogs tocados e deixar em `docs/05-decisoes.md` qualquer pergunta que ficou aberta. O contêiner de uma sessão na nuvem é descartável: o que não foi para o GitHub não existe.

---

# O site EmDash (guia que vem do template `starter-cloudflare`)

O texto abaixo é o `AGENTS.md` do template oficial, mantido em inglês como veio. Vale para o trabalho no site em si: páginas, schema, seed, queries.

This is an EmDash site -- a CMS built on Astro with a full admin UI.

## Commands

```bash
pnpm dev              # Start the Astro dev server
npx emdash types      # Regenerate TypeScript types from a running site
```

The admin UI is at `http://localhost:4321/_emdash/admin`.

## Key Files

| File                     | Purpose                                                                            |
| ------------------------ | ---------------------------------------------------------------------------------- |
| `astro.config.mjs`       | Astro config with `emdash()` integration, database, and storage                    |
| `src/live.config.ts`     | EmDash loader registration (boilerplate -- don't modify)                           |
| `seed/seed.json`         | Schema definition + demo content (collections, fields, taxonomies, menus, widgets) |
| `emdash-env.d.ts`        | Generated types for collections (auto-regenerated on dev server start)             |
| `src/layouts/Base.astro` | Base layout with EmDash wiring (menus, search, page contributions)                 |
| `src/pages/`             | Astro pages -- all server-rendered                                                 |

## Skills

Agent skills are in `.agents/skills/`. Load them when working on specific tasks:

- **building-emdash-site** -- Querying content, rendering Portable Text, schema design, seed files, site features (menus, widgets, search, SEO, comments, bylines). Start here.
- **creating-plugins** -- Building EmDash plugins with hooks, storage, admin UI, API routes, and Portable Text block types.
- **emdash-cli** -- CLI commands for content management, seeding, type generation, and visual editing flow.

## Documentation

The EmDash docs are available as an MCP server at `https://docs.emdashcms.com/mcp`. When you need to verify an API, hook, config option, field type, or pattern, call `search_docs` against the live documentation rather than relying on training-data recall. The docs reflect current behaviour; assumptions may not.

This template ships with `.mcp.json`, `.cursor/mcp.json`, and `.vscode/mcp.json` so Claude Code, Cursor, and VS Code auto-discover the docs server. Other tools (OpenCode, Windsurf, etc.) need a manual one-time setup -- see [docs.emdashcms.com/docs-mcp](https://docs.emdashcms.com/docs-mcp).

## Rules

- All content pages must be server-rendered (`output: "server"`). No `getStaticPaths()` for CMS content.
- Image fields are objects (`{ src, alt }`), not strings. Use `<Image image={...} />` from `"emdash/ui"`.
- `entry.id` is the slug (for URLs). `entry.data.id` is the database ULID (for API calls like `getEntryTerms`).
- When Astro's cache is enabled, pass content-query hints to `Astro.cache.set(cacheHint)`. Use the `WithCacheHint` variants for site settings, menus, taxonomies, and widget areas rendered by cached routes.
- Taxonomy names in queries must match the seed's `"name"` field exactly (e.g., `"category"` not `"categories"`).

## This Template

A general-purpose starting point with posts, pages, categories, and tags. Less opinionated than the themed templates -- a base for sites that want to define their own design.

There is intentionally no `theme.css`, no custom font configuration, no styled layouts beyond browser defaults. The home, posts index, post detail, page, category, and tag pages all render with minimal styling. Start here if you want full control over the visual language; start with `blog`, `portfolio`, or `marketing` if you want a designed template to customise.

## Pages

| Page        | Path               | What it shows                                  |
| ----------- | ------------------ | ---------------------------------------------- |
| Home        | `/`                | Site title + tagline, links into Posts / About |
| All posts   | `/posts`           | Post list                                      |
| Post detail | `/posts/[slug]`    | Post content                                   |
| Page        | `/[slug]`          | Static page content (e.g. `/about`)            |
| Category    | `/category/[slug]` | Posts filtered by category                     |
| Tag         | `/tag/[slug]`      | Posts filtered by tag                          |

## Schema

- `posts` collection: `title`, `featured_image`, `content` (Portable Text), `excerpt` (text).
- `pages` collection: `title`, `content` (Portable Text).
- Taxonomies: `category`, `tag`.
- Single `primary` menu.

Site settings have `title` and `tagline`.

## Visual character

None imposed. Define your own.

This template ships without:

- `src/styles/theme.css` -- create one and import it from `Base.astro` if you want CSS-variable theming.
- Fonts in `astro.config.mjs` -- the `fonts:` array is empty. Add Google Fonts entries with `cssVariable` bindings if you want web fonts.
- A `components/` directory with styled cards / tag lists / etc. -- build them as needed.

## What to do here

If you're customising this template, the work is to add design, not to subtract it. Reasonable first moves:

1. Decide on one display + one body typeface, add them to `astro.config.mjs`, bind them to `--font-display` and `--font-body` CSS variables.
2. Create `src/styles/theme.css` with your colour palette, type scale, and spacing tokens.
3. Import it from `Base.astro`, then add any page-specific styles in the relevant Astro page.
4. Build page-specific styles in each Astro page's `<style>` block, referencing the CSS variables.

If you want a designed template instead, switch to `blog`, `portfolio`, or `marketing` -- each ships with a full visual system you can re-skin via `theme.css`.

## What not to do

- Don't treat this as a finished design. The unstyled output is intentional; shipping it as-is looks unfinished because it is.
- Don't add component libraries (Tailwind UI, shadcn, etc.) without considering what they bring with them. The template is small on purpose.
- Don't recreate the blog template's three-column reading view here. If that's what you want, start from `blog`.
