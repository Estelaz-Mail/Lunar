---
slug: seguranca
group: Ir além
title: Segurança
description: Escapamento, CSP, cabeçalhos e o que ainda é da aplicação.
---

## Escapamento {#escapamento}

Texto no template é escapado por padrão, no corpo, em atributos e em strings interpoladas. `{@html}` é a única forma de inserir marcação sem escapar, e a sintaxe é distinta para o ponto de uso deixar isso explícito. Os dados da página viajam num bloco `application/json`, que o navegador não executa.

## Content Security Policy {#csp}

A política é gerada a partir da resposta, com `default-src 'none'` como ponto de partida para documentos. Um script embutido é autorizado pelo SHA-256 dos seus bytes, nunca por nonce e nunca com `unsafe-eval`. O Fengari vendorizado não contém `eval` nem `new Function`.

Respostas que não são documentos usam uma política mais fechada, com `frame-ancestors 'none'` e `sandbox`.

## Cabeçalhos {#cabecalhos}

O servidor define `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`, as políticas de origem cruzada e um `Permissions-Policy` que desliga APIs de dispositivo.

## Limite de requisições {#limite}

Há um limitador por endereço, em balde de fichas, com limites separados para páginas, arquivos e escritas. O rastreamento é limitado e entradas inativas são descartadas. Num teste de carga, suba o servidor com `RATE_LIMIT=0`.

## Arquivos públicos {#estaticos}

Caminhos são normalizados antes de qualquer leitura, e nada fora da raiz de `static/` é servido. Cada arquivo sai com `ETag` e `Cache-Control`, e com `Vary: Accept-Encoding`, porque o servidor envia o irmão `.br` ou `.gz` quando ele existe e o pedido aceita.

:::warn
Nada disso substitui validar o que chega nos endpoints. O framework trata do transporte e do documento; o significado dos dados é da aplicação.
:::
