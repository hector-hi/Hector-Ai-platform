# Do zero ao ar — roteiro completo

Tudo o que é preciso para sair de um repositório vazio e chegar a um site EmDash publicado, na ordem. Quase tudo é um comando da skill. O que **não** é comando são os passos que só o dono da conta pode dar — estão marcados com 👤 e são três.

## Visão geral

| # | Passo | Quem | Comando |
|---|---|---|---|
| 1 | Criar o site | agente | `scripts/init-site.sh --name <worker>` |
| 2 | Token da Cloudflare | 👤 | painel da Cloudflare |
| 3 | Provisionar D1 e R2 | agente | `scripts/provision.sh` |
| 4 | Instalar os workflows | agente | `scripts/install-workflows.sh` |
| 5 | Conferir tudo localmente | agente | `scripts/pipeline.sh check` |
| 6 | Commit e push | agente | git |
| 7 | Secret e variável no GitHub | 👤 | Settings do repositório |
| 8 | Ver o alvo | agente ou 👤 | workflow **Deploy** → `status` |
| 9 | Conferir o alvo e publicar | 👤 | workflow **Deploy** → `deploy` |
| 10 | Setup do admin | 👤 | navegador, **imediatamente** |

Depois do primeiro, todo deploy é só o passo 9.

## 1. Criar o site

```bash
scripts/init-site.sh --name <worker>
```

Usa o scaffolder oficial (`npm create emdash@latest`), aplica os nomes (Worker e D1 = `<worker>`, R2 = `<worker>-media`), liga o sandbox de plugins, ajusta o `.gitignore` e instala as dependências. Opções: `--template blog|marketing|portfolio`, `--bucket <nome>`, `--no-sandbox`, `--dir <pasta>`.

Se o scaffolder não alcançar a rede (ele baixa de `github.com/emdash-cms/templates`), o script diz como seguir: clonar o repositório do EmDash e repetir com `--from-upstream <pasta>`. O resultado é o mesmo.

Recusa-se a rodar onde já existe um `wrangler.jsonc`.

## 2. 👤 Token da Cloudflare

No painel da Cloudflare: *My Profile → API Tokens → Create Token → Custom token*, com as permissões de conta:

| Permissão | Nível | Para quê |
|---|---|---|
| Workers Scripts | Edit | publicar o Worker |
| D1 | Edit | migrations e Time Travel |
| Workers R2 Storage | Edit | bucket de mídia |
| Workers KV Storage | Edit | namespace de sessões, criado no primeiro deploy |

Anotar também o **Account ID** (aparece na página inicial da conta e na URL do painel).

O token é segredo: vai para o GitHub (passo 7) ou para o ambiente de quem roda os scripts. **Nunca em arquivo do repositório nem em conversa.**

## 3. Provisionar

```bash
export CLOUDFLARE_API_TOKEN=...  CLOUDFLARE_ACCOUNT_ID=...
scripts/provision.sh            # --check para só ver o que existe
```

Cria o D1 e o R2 com os nomes do `wrangler.jsonc` e fixa o `database_id` no arquivo. Idempotente: o que já existe é reaproveitado. `--location <hint>` escolhe a região do D1, que **não pode ser mudada depois**.

Num ambiente sem acesso à API da Cloudflare, o mesmo se faz por um conector MCP da Cloudflare (criar o D1 e o R2 com os mesmos nomes) seguido de:

```bash
node scripts/lib/site-config.mjs set-database-id <uuid>
```

## 4. Workflows

```bash
scripts/install-workflows.sh
```

Gera `.github/workflows/ci.yml` e `deploy.yml` a partir de `templates/workflows/`. Os arquivos gerados não se editam: muda-se o template e reinstala-se. O `pipeline.sh check` falha se divergirem.

## 5 e 6. Conferir e enviar

```bash
scripts/pipeline.sh check
git add -A && git commit -m "..." && git push
```

O push dispara o CI, que roda exatamente o mesmo `pipeline.sh check`.

## 7. 👤 Configurar o repositório no GitHub

*Settings → Secrets and variables → Actions*:

| Aba | Nome | Valor | Obrigatório |
|---|---|---|---|
| Secrets | `CLOUDFLARE_API_TOKEN` | o token do passo 2 | sim |
| Variables | `CLOUDFLARE_ACCOUNT_ID` | o Account ID | sim |
| Variables | `EMDASH_TARGET_FINGERPRINT` | o fingerprint do passo 8 | não — pode ser digitado ao disparar |
| Variables | `EMDASH_DEPLOY_URL` | URL pública a verificar | não — sem ela, usa a que o deploy imprimir |
| Secrets | `EMDASH_ENCRYPTION_KEY` | saída de `npx emdash secrets generate` | não no primeiro deploy |

Sobre a `EMDASH_ENCRYPTION_KEY`: ela cifra os settings secretos dos plugins e **não fica no banco**. Guardar uma cópia fora da Cloudflare e do GitHub — os dois só a aceitam, não a devolvem. Sem ela, um banco restaurado tem esses settings ilegíveis.

## 8. Ver o alvo

*Actions → Deploy → Run workflow → `status`.*

Só leitura. O resumo do job mostra a conta, o banco e o **fingerprint** do alvo.

## 9. 👤 Conferir e publicar

Ler o resumo do passo 8. A conta e o banco são os seus? Então:

*Actions → Deploy → Run workflow → `deploy`*, colando o fingerprint no campo `fingerprint` (ou gravando-o antes na variável `EMDASH_TARGET_FINGERPRINT`, para não colar de novo nos próximos).

Este passo é humano de propósito. O fingerprint é a guarda contra migrar o banco errado; ele não é segredo, mas confirmá-lo sem olhar joga a guarda fora. **Não automatizar.** Só precisa ser refeito quando o alvo mudar.

O job roda `pipeline.sh deploy`: os mesmos checks do CI e, se passarem, backup → migrate → deploy → check → verificação → run record. As evidências (bookmark do Time Travel, logs, run record) ficam como artefato do job por 90 dias.

## 10. 👤 Setup do admin — imediatamente

Abrir `<url>/_emdash/admin/` e concluir o assistente. **A primeira pessoa a terminar vira administradora**, e a URL é pública.

As passkeys criadas ali ficam presas a esse endereço. Se o site for mudar para um domínio próprio, ler antes "Custom domains" em `deployment/cloudflare.mdx` do EmDash.

## Se algo falhar

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `credenciais` sai com 3 | secret ou variável ausente | passo 7 |
| `deploy` sai com 4 antes de tudo | sem fingerprint | passos 8 e 9 |
| `deploy` sai com 4 no migrate | fingerprint não bate com o alvo | **parar**; rodar `status` e conferir o que mudou |
| `deploy` sai com 3 | bookmark do Time Travel não obtido | conferir a permissão D1 do token; não migrar sem ponto de retorno |
| `verify` sai com 5 | site não responde | ver `wrangler tail`; o run record e o log estão no artefato |
| CI falha em `workflows` | `.github/workflows/` editado à mão | `scripts/install-workflows.sh` |

Todo erro que este quadro não explicar é um gap: incorporá-lo à skill (seção 4 do `SKILL.md`).
