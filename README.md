# Hector AI Platform

Infraestrutura de empresa grande, operada por uma pessoa só.

O substrato já existe e é aberto: o [EmDash](https://github.com/emdash-cms/emdash), um CMS full-stack em TypeScript sobre Astro que roda na Cloudflare como **um único Worker** — banco, mídia, coedição, agendamento, permissões, revisões, plugins isolados e um servidor MCP para agentes, tudo já pronto. Este repositório não reconstrói nada disso. Ele guarda o que é nosso: as decisões, a costura e o pipeline que mantém tudo honesto.

> **A regra da casa:** o código nosso é cola, costura ou algo original — nunca infraestrutura, nunca substrato. Se o EmDash já faz, usamos o do EmDash.

## Estado atual

| O quê | Situação |
|---|---|
| Documentação (v2) | Pronta — [`docs/`](docs/README.md) |
| Skill do pipeline `emdash-cicd` | v1.3.0 — [`skills/emdash-cicd/`](skills/emdash-cicd/SKILL.md). Preflight e gates já rodaram de verdade; backup, deploy e pós-deploy ainda não |
| Site EmDash (o Worker) | Criado na raiz (EmDash 1.5.0, sandbox ligado). Build e gates passam. **Ainda não publicado** |
| Recursos Cloudflare | D1 `hector-ai-platform` e R2 `hector-ai-platform-media` criados. Worker ainda não |
| Workflows do GitHub Actions | [`ci.yml`](.github/workflows/ci.yml) (gates em todo push) e [`deploy.yml`](.github/workflows/deploy.yml) (manual) |

O próximo passo e o que ele espera de decisão estão em [`docs/05-decisoes.md`](docs/05-decisoes.md).

## Por onde começar

| Se você quer… | Leia |
|---|---|
| Entender a ideia em cinco minutos | [`docs/00-visao.md`](docs/00-visao.md) |
| Saber o que é cada peça e por que ela existe | [`docs/01-arquitetura.md`](docs/01-arquitetura.md) |
| Instalar, passo a passo | [`docs/02-instalacao.md`](docs/02-instalacao.md) |
| Operar: custo, backup, riscos, monitoramento | [`docs/03-operacao.md`](docs/03-operacao.md) |
| Ver o que vamos construir de original | [`docs/04-suite-de-plugins.md`](docs/04-suite-de-plugins.md) |
| Decidir (ou ver o que já foi decidido) | [`docs/05-decisoes.md`](docs/05-decisoes.md) |
| Rodar o pipeline | [`skills/emdash-cicd/SKILL.md`](skills/emdash-cicd/SKILL.md) |
| Continuar o trabalho sendo um agente de IA | [`AGENTS.md`](AGENTS.md) |

## Mapa do repositório

```text
README.md              esta página
astro.config.mjs       ┐
wrangler.jsonc         │ o site EmDash — um Worker
src/  seed/            ┘ (template starter-cloudflare; aqui só mudam nomes e o sandbox)
.github/workflows/     CI (gates) e Deploy (manual), ambos chamando a skill
.agents/skills/        skills oficiais do EmDash que vêm com o template
AGENTS.md              regras e contexto para qualquer agente que continue o trabalho
docs/                  documentação viva (versionada em docs/CHANGELOG.md)
  origem/2026-11-13/   os documentos originais, intocados — a referência histórica
skills/emdash-cicd/    o pipeline como código: 6 scripts + contrato + changelog
.claude/skills/        atalho para a skill, para o Claude Code carregá-la sozinho
```
