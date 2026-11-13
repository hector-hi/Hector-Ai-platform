# CHANGELOG — documentação

Toda mudança em `docs/` entra aqui no mesmo commit. Convenção de versão em [`README.md`](README.md#versionamento). A skill `emdash-cicd` tem changelog próprio em `skills/emdash-cicd/CHANGELOG.md`.

## [2.2.0] — 2026-11-13

- `05-decisoes.md`: decisão A16 (a skill é o manual executável; o deploy começa pelos checks do CI) e pendência nova **D11 — Cloudflare Artifacts**, com o que é, três usos possíveis e uma recomendação à espera de resposta. O que bloqueia o primeiro deploy passa a apontar para o roteiro da skill.
- `02-instalacao.md`: atalho para os comandos da skill; os workflows são descritos como gerados.

## [2.1.0] — 2026-11-13

### Decisões registradas (`05-decisoes.md`)
- A10 nomes; A11 domínio gratuito por enquanto, com a consequência para as passkeys; A12 deploy pela skill, no GitHub Actions; A13 site criado a partir do template; A14 sandbox ligado; A15 onde vive a skill.
- Pendências reescritas: o que bloqueia agora é a configuração das credenciais no GitHub e a conferência do fingerprint.

### Atualizado
- `02-instalacao.md`: estado real da Fase 1; seção do GitHub Actions passa a descrever os workflows que existem, com a tabela de secrets e variáveis; nota sobre o que `--sandboxed-plugins` faz e não faz.
- `README.md` e `AGENTS.md` da raiz: estado atual. O `AGENTS.md` ganha, ao final, o guia do site que vem do template.
- Duas perguntas técnicas novas em aberto (sandbox no site publicado; provisionamento do KV `SESSION`).

## [2.0.0] — 2026-11-13

Reorganização da série e revisão contra o código-fonte do EmDash (cópia de 12/11/2026).

### Mudou a estrutura
- A série deixa de ser organizada por tipo de entregável e passa a ser organizada pela pergunta do leitor: visão, arquitetura, instalação, operação, plugins, decisões. A tabela de correspondência está em `README.md`.
- Novo `00-visao.md`: a ideia, o mapa "não construir", o que é nosso, os princípios.
- Novo `05-decisoes.md`: decisões tomadas, pendentes, bloqueadores externos e perguntas técnicas em aberto, num lugar só. Antes estavam espalhados por três documentos.
- `PROMPT-CONTINUACAO.md` vira `AGENTS.md` na raiz.
- Diagramas em Mermaid: arquitetura do Worker, ecossistema, ordem das fases, sequência de deploy, modelo do grafo, sequência de um workflow, painel de decisões.
- Legenda de evidência: cada afirmação marca se veio do código, da doc upstream, da v1 sem reconferência, ou se é decisão nossa.
- Enquadramento: de "instalação corporativa" para a plataforma de uma pessoa. A arquitetura não muda.

### Corrigido (fatos conferidos no código)
- **Direção da dependência labeler ↔ aggregator.** A v1 desenhava a seta do aggregator para o labeler. No código, o labeler é quem tem o service binding e chama o aggregator.
- **Configs Wrangler: 26, não 28.**
- **Cron Triggers na instalação integral: 4, não 3** (o perf-monitor tem `*/30`).
- **Checklist de limpeza de IDs do upstream estava incompleta.** Faltavam `infra/perf-monitor` (com `account_id` e `database_id`, e ele faz parte da Fase 5), `infra/discord-bot`, `infra/flue-review`, `infra/do-demo`, `infra/do-solo-demo`. No `release-service`, os audiences do Access são três variáveis, agora nomeadas.
- **`emdash doctor` em projeto D1.** A v1 listava "doctor passando" como critério. O check `database` dele falha sempre em D1; o critério certo é o check `scheduler wiring`.
- **URL do pós-deploy.** A v1 assumia `<worker>.workers.dev`. O endereço real inclui o subdomínio da conta.
- **Capability de rede dos plugins.** A v1 citava o `webhook-notifier` como modelo de `network:request` com lista de hosts. Ele usa `network:request:unrestricted`. A recomendação para os nossos plugins (lista restrita) fica, agora com o motivo certo.
- **Nomes reais de recursos** do labeler, do release-service e do perf-monitor, lidos dos configs.

### Acrescentado
- Flag `--sandboxed-plugins` do scaffolder, que entrega a Fase 2 já na criação do projeto.
- Exit codes do `emdash migrate` (2, 3, 4, 130).
- Procedimento de lock de migration preso (`--take-over-lock`).
- Modos de migration do runtime (`auto` → `check` → `manual`) e o limite de ~5.000 linhas.
- Diferença entre Worker Previews e ambiente nomeado.
- `EMDASH_SITE_URL` em vez de `siteUrl`, e por quê.
- No estudo de plugins: o aviso de que escrita condicional não garante exatamente-uma-vez para efeitos externos, e a regra de idempotência que decorre dele; a restrição de que plugin não cria definição de taxonomia; o que o host de teste não cobre; o fato de que o ator do hook não identifica a origem do save.
- Riscos R10 (primeiro run real da skill) e R11 (corrida pelo setup).
- Decisões A7, A8, A9 e as pendências novas: nomes, forma de criar o site, onde vive a skill.

### Não reconferido nesta revisão
- **Todos os preços.** Marcados **[v1]**.
- Estimativas de prazo.
- Detalhes das fases 3 a 5 além dos recursos declarados nos configs (Access, OIDC, PDS, variáveis do aggregator).
- O procedimento de dump SQL offsite.

### Preservado
- Os quatro documentos originais e o prompt de continuação, intocados, em `origem/2026-11-13/`.

## [1.0.0] — 2026-11-13

Série original: `EMDASH-INSTALACAO-INTEGRAL.md`, `EMDASH-CONSIDERACOES-FINAIS.md`, `EMDASH-PLUGIN-SUITE-ESTUDO.md`, `PROMPT-CONTINUACAO.md`. Preservada em `origem/2026-11-13/`.
