# 03 — Operação

Quanto custa, como se recupera, o que pode dar errado e o que vigiar.

## 1. Custo

> **Todos os preços desta seção são [v1]:** levantados em 13/11/2026 nas páginas oficiais e **não reconferidos** nesta revisão. Antes de decidir por custo, conferir em [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [R2](https://developers.cloudflare.com/r2/pricing/), [Durable Objects](https://developers.cloudflare.com/durable-objects/platform/pricing/) e [planos](https://www.cloudflare.com/plans/). Reconferir a cada trimestre.

### O que importa para você

| Cenário | Estimativa mensal |
|---|---|
| **Fases 1–2: site + sandbox**, tráfego baixo | **~US$ 5–8** |
| O mesmo com ~1 M de requisições e 20 GB de mídia | ~US$ 10–20 |
| + Registry próprio (Fase 3) | + US$ 10–30 |
| + Publicação delegada (Fase 4) | + US$ 5–15 |
| Tudo | ~US$ 30–70 |

Os US$ 5 de base são a assinatura Workers Paid, que cobre a conta inteira.

### Preços unitários

| Produto | Uso aqui | Incluído no Paid | Excedente |
|---|---|---|---|
| Workers | Todos | 10 M req/mês; 30 M ms de CPU | US$ 0,30/M req; US$ 0,02/M ms |
| Dynamic Workers | Isolados de plugins | — | US$ 0,002 por isolado instanciado |
| D1 | Banco | — | US$ 0,75/GB-mês; US$ 0,001/M linhas lidas; US$ 1,00/M escritas |
| R2 | Mídia | — | US$ 0,015/GB-mês; Classe A US$ 4,50/M; Classe B US$ 0,36/M |
| Durable Objects | Coedição; DOs do registry | — | US$ 0,15/M req; **US$ 12,50/M GB-s de duração** |
| KV | Sessões | — | US$ 0,50/M leituras; **US$ 5,00/M escritas** |
| Filas | Registry, perf-monitor | — | US$ 0,40/M operações |
| Workflows | Labeler, release-service | 500 mil passos/mês | US$ 0,80/100 mil |
| Images | Transformações | **5.000 únicas/mês** (plano Free do Images) | cobradas à parte |

### Onde o custo surpreende

1. **Duração de Durable Object** é a maior alavanca. Um DO acordado em memória cobra por segundo; hibernando, não. O `RecordsJetstreamDO` do aggregator mantém um WebSocket aberto. Só interessa se você fizer a Fase 3 — e aí, validar a hibernação antes de aceitar a fase.
2. **Transformações de imagem** contam por combinação única de imagem × parâmetros, uma vez por mês. 500 imagens em 2 tamanhos = 1.000. Passando de 5.000, as já cacheadas continuam servindo e as **novas falham com erro `9422`**. **[doc: `deployment/cloudflare.mdx`]**
3. **Escrita em KV** é o item mais caro por unidade. Sessões autenticadas escrevem em KV.
4. **CPU estoura antes de requisições.** Os dois têm franquia; a de CPU costuma acabar primeiro.

**No primeiro dia:** criar alerta de orçamento nas páginas de produto da Cloudflare.

## 2. Recuperação

### O ponto de retorno

Antes de **toda** migration. O `backup-point.sh` da skill faz os passos 1 e 2 e lembra do 3.

```bash
# 1. Bookmark do banco — guardar a saída inteira junto do deploy
npx wrangler d1 time-travel info <nome-do-banco>

# 2. Mídia — com credenciais só de leitura, para FORA da conta de produção
aws s3 sync s3://<bucket> ./backup-midia \
  --endpoint-url https://<account-id>.r2.cloudflarestorage.com

# 3. A lista de rotação da EMDASH_ENCRYPTION_KEY — em gerenciador de segredos, à parte
```

O Time Travel guarda pontos por **7 dias no plano Free e 30 dias no Paid**. Janela maior pede dump SQL fora da Cloudflare. **[doc: `guides/backups.mdx`]**

### Restaurar

```bash
# Parar de escrever no site antes. Sobrescreve o banco no lugar e cancela queries em voo.
npx wrangler d1 time-travel restore <nome-do-banco> --bookmark="<bookmark-pré-migration>"
```

O comando imprime o bookmark anterior — guardá-lo, para poder desfazer o próprio restore.

Depois: restaurar o artefato do Worker correspondente, a mídia e as chaves **antes** de reabrir o tráfego. Conferir login, leitura de conteúdo, schema, um setting cifrado de plugin e uma escrita. **[doc]**

Mídia se restaura **sempre num bucket de recuperação vazio**, nunca por cima do bucket em produção.

### O que não fazer

- **Não reverter migration à mão.** Não apagar linhas de `_emdash_migrations`; não rodar `down()`. **[doc]**
- **Não contar com o export JSON como backup.** Não existe restore. Ele omite usuários, dados e segredos de plugins, mídia e comentários. **[v1]**
- **Não achar que voltar o Worker desfaz o schema.** Não desfaz.
- **Não reexecutar `emdash migrate` às cegas depois de uma interrupção.** Rodar `--status` no mesmo alvo e ler. A única exceção documentada é a migration `079_datetime_normalization`, que retoma de onde parou. **[doc]**

### Lock de migration preso

Acontece quando um job é cancelado no meio do `emdash migrate`. Depois de um minuto com o lock preso, um site em modo `auto` passa a responder 503. **[doc]**

```bash
pnpm emdash migrate --status                       # mostra o lock e seu id
pnpm emdash migrate --take-over-lock <id>          # assume o lock e aplica as pendentes
```

Antes, ter certeza de que nada mais está migrando aquele banco. Num site em `auto`, preferir `--take-over-lock` a `--release-lock`: liberar o lock deixa uma requisição pegá-lo primeiro.

### Dump SQL fora da Cloudflare

`wrangler d1 export --remote` falha com as tabelas virtuais FTS5 do índice de busca. Exportar por nome de tabela, e conferir se há statement com 100 KB ou mais — o D1 os rejeita na importação. O procedimento completo está em `guides/backups.mdx` do EmDash. **[v1]**

### Mover ou clonar o site

`emdash site export` / `import` transfere o site inteiro — modelo de conteúdo, conteúdo, histórico e mídia, sem usuários nem segredos — com um plano conferido por digest. Serve para levar staging a produção e como recuperação parcial. Ver a skill upstream `emdash-cli`. **[v1]**

## 3. Riscos

| ID | Risco | Prob. | Impacto | O que fazer |
|---|---|---|---|---|
| R4 | Passkeys presas ao hostname errado (setup feito no `workers.dev`) | Média | Médio | Setup no domínio final, ou `EMDASH_SITE_URL` antes |
| R5 | Migration interrompida | Baixa | Alto | Bookmark antes; CI serializado; `--status` antes de qualquer retry |
| R7 | Mais de 5.000 transformações de imagem no mês | Média | Médio | Vigiar o uso; plano pago do Images se a mídia crescer |
| R8 | Cron novo ou alterado demora a ativar | Certa | Baixo | Não é defeito. Não mexer em cron perto de uma publicação agendada |
| R9 | Skills upstream mudam num upgrade | Média | Baixo | Refletir na nossa skill na execução seguinte |
| R10 | **O primeiro run real do pipeline revela falhas dos scripts** *(novo)* | **Alta** | Baixo | Esperado: a skill nunca rodou num deploy real. Fazer o primeiro deploy num alvo descartável; incorporar cada achado |
| R11 | **Corrida pelo setup em URL pública** *(novo)* | Baixa | Alto | Concluir o assistente imediatamente após o primeiro deploy — em produção e em cada preview |
| R1 | Custo de duração de DO no aggregator | Média | Alto | Só na Fase 3. Validar hibernação; alerta de orçamento |
| R2 | `blob-proxy` e CDN externos travam o registry próprio | Alta | Médio | Só na Fase 3. Consumir o hospedado até resolver |
| R3 | Hostname do aggregator divergente | Média | Médio | Só na Fase 3. Decidir um, registrar |
| R6 | `release-service` experimental muda de contrato | Média | Baixo | Só na Fase 4. Tratar como piloto |

## 4. O que vigiar

1. **Alertas de orçamento** — criados no primeiro dia.
2. **`wrangler tail`** — confirma o cron: publicações agendadas aparecem no log do handler `scheduled`. Cada execução espera até cerca de um minuto por entradas próximas, então execuções consecutivas podem se sobrepor no log; é normal. **[doc]**
3. **O painel admin** — avisa quando uma entrada agendada passou do horário sem execução. É o canário do agendador. **[v1]**
4. **`postdeploy.sh` em toda release** — página pública, admin, `migrate --check`, bindings no config gerado.
5. **Run records** — `skills/emdash-cicd/runs/`: o que rodou, com que resultado, o que faltou.
6. **Observability** — ligar em `wrangler.jsonc` (`observability.enabled`).

## 5. Limites que mordem

| Limite | Valor | Onde aparece |
|---|---|---|
| Migration grande em runtime | ~5.000 linhas de conteúdo | Acima disso o Worker em `auto` responde 503 até rodar `emdash migrate` **[doc]** |
| Statement no D1 | < 100.000 bytes | Importação de dump **[v1]** |
| Lock de migration | espera 10 s | Segundo job simultâneo falha **[doc]** |
| CPU por invocação | 30 s; 15 min em cron e consumidor de fila | Backfills **[v1]** |
| Subrequisições | 1.000 no Paid | Migrations em runtime, plugins que fazem muitas chamadas **[v1]** |

## 6. Manter atualizado

O atualizador oficial é a skill upstream `upgrading-emdash`, apoiada no pacote `upgrade-emdash`. Ele também atualiza as skills do projeto em `.agents/skills/` e gera uma ordem de serviço em `.emdash/UPGRADE.md`. **[v1]**

Dois pontos de `deployment/updating.mdx` **[doc]**:

- **Os arquivos do template não são atualizados** por um upgrade. O que veio do scaffolder é seu a partir do primeiro commit.
- A migration `095_plugin_storage_unique_scope` é exceção à regra "migrar antes do deploy": pede janela de manutenção, porque builds antigos podem recriar as constraints que ela troca.

Depois de qualquer upgrade, a próxima execução do pipeline confere se a nossa skill ainda diz a verdade sobre as upstream.
