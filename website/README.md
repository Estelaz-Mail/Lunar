# Lunar — site oficial

Site de **https://lunar.estelaz.com**, feito com componentes `.lunar`, lógica Lua e CSS: home, exemplos reativos e doze páginas de documentação em português. Renderização no servidor, hidratação pelo moonlight, hospedagem em **Cloudflare Workers**.

Ele mora dentro do repositório do framework e usa o framework que está ao lado dele, não uma cópia baixada: o que você muda em `lunar/` vale no site na mesma hora, e o site é um teste de que o framework funciona.

## Desenvolvimento

Requisitos: Lua 5.4 (`lua5.4`), Node.js 22+ e npm. LuaSocket não é necessário, porque o Wrangler é quem serve.

```sh
npm ci
npm run dev
```

Abra o endereço local impresso pelo Wrangler, normalmente `http://127.0.0.1:8787`. Após editar componentes ou a documentação, execute `npm run build` em outro terminal; o Wrangler recarrega o pacote. Alterações apenas em CSS também precisam do build para copiar os assets.

`scripts/lunar.sh` usa o diretório acima deste como framework, que é a raiz do repositório. `LUNAR_FRAMEWORK_DIR` aponta para outro checkout quando for preciso, e `LUA` escolhe o interpretador da etapa de build.

## Validação

```sh
npm run check
npm test
npm run deploy:check
```

`check` compila os componentes. `test` gera o pacote e verifica HTML, idioma, metadados, CSP, redirecionamento, erros 404 e múltiplos assinantes reativos. `deploy:check` valida o bundle com `wrangler deploy --dry-run`, sem publicar.

## Publicação no Workers

```sh
npx wrangler login
npm run deploy
```

O arquivo `wrangler.jsonc` da raiz é a configuração permanente. Define o Worker `lunar-website`, o binding `ASSETS`, observabilidade e o Custom Domain `lunar.estelaz.com`. A zona `estelaz.com` deve estar ativa na conta Cloudflare utilizada e o usuário deve ter permissão para gerenciar o Worker e o domínio. A rota é `lunar.estelaz.com/*` na zona `baioneta.com`, para onde `lunar.estelaz.com` aponta por CNAME.

O build usa o gerador nativo do Lunar, que produz `.lunar/workers/`. Esse diretório é descartável: não edite sua configuração manualmente nem use o deploy do package.json gerado; use os comandos da raiz para preservar o domínio e os ajustes de compatibilidade.

Para Workers Builds: instalação `npm ci`, build `npm run build`, deploy `npx wrangler deploy`. O ambiente de build precisa fornecer Lua 5.4; se não fornecer, use um runner com Lua instalado. A aplicação não precisa de banco, secrets nem filesystem em runtime.

## Estrutura

- `orbit/`: páginas, probes e shell compartilhado.
- `lib/`: componentes reutilizáveis e documentação editorial em `docs.lua`.
- `static/`: CSS, marca original, fonte local, robots e sitemap.
- `scripts/`: bootstrap do framework, empacotamento e verificações.
- `lunar.json`: nome, idioma e versão do site.
- `wrangler.jsonc`: configuração de produção do Cloudflare Workers.

O conteúdo está baseado no código e README da revisão fixada do framework. A documentação não promete recursos ainda não implementados. O HTML da documentação é conteúdo editorial confiável do próprio projeto; não há execução de código fornecido pelo visitante.

## Compatibilidade com a revisão do Lunar

O empacotamento declara as opções de `lunar.json` explicitamente, pois a revisão fixada ainda não carrega esse manifesto automaticamente. Usa a raiz absoluta da aplicação para que os imports coincidam com o registro de componentes congelado.

O script `scripts/build.mjs` aplica dois ajustes exclusivamente aos arquivos gerados, sem editar o checkout do Lunar:

1. Substitui dois construtores `Function` estáticos do Fengari por closures equivalentes. Isso permite hidratar com a CSP padrão, sem liberar `unsafe-eval`. O loader opcional de módulos JavaScript dinâmicos do Fengari continua sujeito à CSP e não é usado pelo site.
2. Copia os assinantes de um sinal antes de disparar os efeitos. O runtime original modifica a tabela de assinantes durante a iteração, deixando atualizações de múltiplas dependências inconsistentes. A verificação em `scripts/verify.lua` cobre esse caso.

Os patches verificam a quantidade esperada de correspondências e falham se uma atualização do framework alterar os trechos. Ao atualizar a revisão, revise os ajustes e repita os testes no navegador.

`npm audit` reporta um aviso moderado em `sprintf-js`, transitivo do Fengari, sem correção publicada: [GHSA-hp3w-g68c-fv3c](https://github.com/advisories/GHSA-hp3w-g68c-fv3c). O site não aceita formatos Lua nem código do visitante; os formatos executados são os do código empacotado. Acompanhe a correção no upstream antes de introduzir execução de conteúdo externo.

## Licenças

Código do site: MIT. Marca: assets originais do projeto [Lunar](https://github.com/Glazastyy/Lunar/tree/main/brand), preservados sem redesenho. Fonte Inter distribuída localmente sob SIL Open Font License, em `static/fonts/OFL.txt`.

## Proxy do instalador

`/install.sh` é atendido por `worker/index.mjs` antes da aplicação Lunar. O proxy em `worker/install.mjs` transmite sem alterar os bytes de `https://raw.githubusercontent.com/Glazastyy/Lunar/refs/heads/main/install.sh` e guarda respostas HTTP 200 na Cache API do Workers por **300 segundos**. O cache é local ao datacenter; não usa banco ou KV. Query strings compartilham a mesma chave, sem encaminhar headers do visitante ao GitHub.

Aceita GET e HEAD. O header `X-Cache` indica `MISS` ou `HIT`. Falhas do upstream retornam 502 com `Cache-Control: no-store`; os demais métodos retornam 405. O timeout do fetch é de 10 segundos. A documentação usa o endereço do site para instalar:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://lunar.estelaz.com/install.sh | sh
```
