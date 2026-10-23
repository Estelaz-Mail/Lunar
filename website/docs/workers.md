---
slug: workers
group: Ir além
title: Cloudflare Workers
description: Como empacotar a mesma aplicação para a borda.
---

```
lunar workers meu-app
```

O comando escreve `.lunar/workers/`, pronto para publicar.

| Caminho          | O que é                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `src/app.lua`    | o runtime, os componentes, os probes e a tabela de rotas num arquivo só |
| `src/worker.mjs` | o ponto de entrada em JavaScript                                        |
| `public/`        | os arquivos públicos, servidos pela plataforma antes do Worker          |
| `wrangler.jsonc` | a configuração do Worker                                                |

## O que muda em uma aplicação congelada {#congelado}

- Nada lê arquivo na hora do pedido. Compilador e servidor HTTP ficam de fora.
- Pedido e resposta cruzam como JSON, então a resposta vira string. Stream junta numa só.
- O limitador vale por isolate.
- WebAssembly vai para `public/` e o navegador monta, não o Worker.

## Publicar {#publicar}

```
cd .lunar/workers
npm install
npx wrangler deploy
```

:::note
A suíte carrega o pacote congelado sem `io` e sem `package.path`, e compara as páginas byte a byte com as do servidor comum. Se o alvo saiu do lugar, esse teste pega.
:::
