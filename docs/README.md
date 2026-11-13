# Documentação — índice e convenções

**Versão da série:** 2.2.0 · **Data:** 13/11/2026 · Histórico em [`CHANGELOG.md`](CHANGELOG.md)

## Ordem de leitura

| # | Documento | A pergunta que ele responde |
|---|---|---|
| 0 | [`00-visao.md`](00-visao.md) | O que é isto e por que não vamos construir quase nada? |
| 1 | [`01-arquitetura.md`](01-arquitetura.md) | Quais são as peças, o que cada uma faz e o que acontece sem ela? |
| 2 | [`02-instalacao.md`](02-instalacao.md) | Em que ordem instalo, com quais comandos? |
| 3 | [`03-operacao.md`](03-operacao.md) | Quanto custa, como recupero, o que pode dar errado? |
| 4 | [`04-suite-de-plugins.md`](04-suite-de-plugins.md) | O que vamos escrever de original? |
| 5 | [`05-decisoes.md`](05-decisoes.md) | O que já está decidido e o que espera decisão? |

O pipeline tem documentação própria junto do código: [`../skills/emdash-cicd/SKILL.md`](../skills/emdash-cicd/SKILL.md).

## De onde veio cada documento

A versão 1 foi escrita por tipo de entregável (um roteiro, um estudo, umas considerações). A versão 2 foi reorganizada pela pergunta que o leitor traz. Nada foi descartado sem registro; os originais estão intocados em [`origem/2026-11-13/`](origem/2026-11-13/).

| Documento v2 | Conteúdo vindo de |
|---|---|
| `00-visao.md` | Novo. Reúne o "mapa não construir" do estudo de plugins e as regras do prompt de continuação |
| `01-arquitetura.md` | `EMDASH-INSTALACAO-INTEGRAL` seções 0-A, 0-B, 6, 12 |
| `02-instalacao.md` | `EMDASH-INSTALACAO-INTEGRAL` seções 0, 1–5, 7–11 |
| `03-operacao.md` | `EMDASH-CONSIDERACOES-FINAIS` seções 1, 3, 4, 5, 7 + backups da instalação |
| `04-suite-de-plugins.md` | `EMDASH-PLUGIN-SUITE-ESTUDO` |
| `05-decisoes.md` | `EMDASH-CONSIDERACOES-FINAIS` seções 2 e 6 + `PROMPT-CONTINUACAO` seção 2 + bloqueadores B1–B6 |
| `../AGENTS.md` | `PROMPT-CONTINUACAO` |

## Legenda de evidência

Toda afirmação sobre como o EmDash ou a Cloudflare se comportam carrega uma marca de origem. O objetivo é simples: quem lê sabe em que pode apoiar o peso.

| Marca | Significa |
|---|---|
| **[código]** | Lido no código-fonte do EmDash (cópia de 12/11/2026), com o caminho do arquivo |
| **[doc]** | Afirmado pela documentação oficial do EmDash, dentro do mesmo repositório |
| **[v1]** | Herdado dos documentos originais e **não reconferido** nesta revisão |
| **[nosso]** | Decisão ou convenção nossa — não é fato da plataforma |

Preços são sempre **[v1]**: foram levantados em 13/11/2026 e não foram reconferidos. Reconferir antes de decidir por custo.

## Versionamento

- **A série tem uma versão** (`MAJOR.MINOR.PATCH`), registrada no topo deste arquivo e em [`CHANGELOG.md`](CHANGELOG.md).
  - MAJOR: reorganização da série ou mudança de uma decisão de arquitetura.
  - MINOR: seção ou documento novo, decisão registrada.
  - PATCH: correção de fato, de texto ou de link.
- **Toda mudança em `docs/` entra no CHANGELOG no mesmo commit.**
- **O histórico fino é o do git** — o CHANGELOG diz o que mudou e por quê; o diff diz exatamente como.
- **A skill tem versão própria** e changelog próprio, porque ela é código executável com contrato.
- **`origem/` nunca é editado.** É o registro do que foi escrito naquele dia.

## Convenções de escrita

- Português, frases diretas, uma ideia por parágrafo.
- Diagramas em Mermaid, que o GitHub renderiza na própria página.
- Comando que o leitor vai copiar fica em bloco de código; nome de arquivo, binding e variável ficam `assim`.
- Onde os originais diziam "a empresa", esta versão diz o que é: a plataforma de uma pessoa. A arquitetura é a mesma; o que muda é quem decide e quanto de cerimônia faz sentido.
