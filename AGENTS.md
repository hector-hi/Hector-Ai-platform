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

- Nada deployado. Nenhum recurso Cloudflare criado. O site ainda não existe neste repositório.
- A skill foi revisada contra o código upstream e testada contra um projeto-stub; **nunca rodou num deploy real**. O primeiro run real vai achar coisas — incorporá-las é o protocolo, não um acidente.
- Caminho crítico: decisões pendentes em `docs/05-decisoes.md` → criar o site (Fase 1) → primeiro run completo do pipeline.

## Ao terminar uma sessão

Commitar no branch de trabalho, atualizar os changelogs tocados e deixar em `docs/05-decisoes.md` qualquer pergunta que ficou aberta. O contêiner de uma sessão na nuvem é descartável: o que não foi para o GitHub não existe.
