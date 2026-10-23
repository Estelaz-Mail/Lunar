---
slug: seguranca
group: Ir além
title: Segurança
description: Escapamento, CSP, cabeçalhos e o que ainda é da aplicação.
---

## Escapamento {#escapamento}

Texto no template sai escapado: corpo, atributo, string interpolada. `{@html}` é a única saída, e existe separado para o código mostrar que aquilo é cru. Os dados da página vão num bloco `application/json`, que o navegador não executa.

## Content Security Policy {#csp}

A política sai da resposta. Documento começa em `default-src 'none'`. Script embutido passa pelo SHA-256 dos bytes, nunca nonce, nunca `unsafe-eval`. O que Lunar entrega não precisa dos dois: o Fengari vendorizado não tem `eval` nem `new Function`.

Resposta que não é documento usa política mais fechada, com `frame-ancestors 'none'` e `sandbox`.

## Cabeçalhos {#cabecalhos}

O servidor manda `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`, política de origem cruzada e um `Permissions-Policy` que desliga API de dispositivo.

## Limite de requisições {#limite}

Tem limitador por endereço, em balde de fichas, com teto separado para página, arquivo e escrita. Rastro é limitado e entrada parada some. Em teste de carga, `RATE_LIMIT=0`. O limitador existe para barrar exatamente o que o teste de carga faz.

## Arquivos públicos {#estaticos}

Caminho é normalizado antes de ler. Nada fora de `static/` sai. Cada arquivo leva `ETag`, `Cache-Control` e `Vary: Accept-Encoding`, porque o servidor manda `.br` ou `.gz` quando existe e o pedido aceita.

:::warn
Isso não substitui validar o que chega nos endpoints. O framework cuida do transporte e do documento. O significado dos dados é da aplicação.
:::
