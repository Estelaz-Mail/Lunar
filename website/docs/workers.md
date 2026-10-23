---
slug: workers
group: Ir além
title: Cloudflare Workers
description: Como empacotar a mesma aplicação para a borda.
---

```
lunar workers meu-app
```

O comando grava o diretório `.lunar/workers/`, pronto para publicar.

| Caminho          | O que é                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `src/app.lua`    | o runtime, os componentes, os probes e a tabela de rotas num arquivo só |
| `src/worker.ts`  | o ponto de entrada em TypeScript                                        |
| `public/`        | os arquivos públicos, servidos pela plataforma antes do Worker          |
| `wrangler.jsonc` | a configuração do Worker                                                |

## O que muda em uma aplicação congelada {#congelado}

- Nada lê um arquivo na hora do pedido: o compilador e o servidor HTTP ficam de fora do pacote.
- A ponte troca pedido e resposta como JSON, então as respostas são montadas como strings; um stream é recolhido numa só.
- O limitador de requisições vale por isolate.
- As partes WebAssembly são gravadas em `public/` e compiladas pelo navegador, não pelo Worker.

## Publicar {#publicar}

```
cd .lunar/workers
bun install
bunx wrangler deploy
```

:::note
A suíte do framework carrega o pacote congelado com `io` e `package.path` retirados e compara as páginas dele, byte a byte, com as do servidor comum.
:::
