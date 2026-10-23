---
slug: renderizacao
group: Aplicação
title: Renderização e hidratação
description: Como o HTML do servidor vira a tela no navegador.
---

## Um componente, dois destinos {#dois-destinos}

O compilador gera, a partir da mesma árvore, um módulo Lua com duas funções: uma escreve HTML no servidor e a outra constrói a interface no navegador. A suíte de testes compara as duas saídas byte a byte; divergência é tratada como defeito.

## O primeiro carregamento {#primeiro-carregamento}

O servidor resolve a rota, executa os probes e renderiza a página. Os dados seguem num bloco `application/json`, que o navegador não executa. O conteúdo já está visível antes de qualquer Lua no cliente.

## Lua 5.4 e moonlight {#moonlight}

A VM oficial Lua 5.4, compilada para WebAssembly, executa Lua no navegador. A ponte JavaScript é do Lunar. O moonlight é o pacote da aplicação no cliente, com componentes, estado e DOM num arquivo só.

## A tomada de controle {#hidratacao}

Na hidratação, o runtime percorre o mesmo template, associa cada nó ao que já está no documento, registra eventos e efeitos, e só reescreve atributos e textos que diferem. Os elementos mantêm identidade, inclusive foco, valor digitado e imagens já carregadas.

Se a árvore não corresponder, o runtime registra a diferença e reconstrói o conteúdo daquele container.

## Atualizações {#atualizacoes}

Textos e atributos são escritos no DOM diretamente, sem árvore virtual. Blocos condicionais e listas sem chave são renderizados de novo quando o que leem muda. Uma lista com chave é reconciliada: as linhas que permanecem conservam seus nós e o estado interno, e apenas o mínimo é reordenado.

## O que o navegador baixa {#custo}

| Peça                        | Sem compressão | Com gzip |
| --------------------------- | -------------- | -------- |
| VM Lua 5.4                  | 196 KiB        | 90 KiB   |
| Ponte JavaScript            | 10 KiB         | 3 KiB    |
| Pacote moonlight do exemplo | 88 KB          | 18 KB    |

A VM, a ponte, o bootstrap e o moonlight são arquivos separados. A VM ainda inclui o parser e as bibliotecas padrão em um módulo único; carregamento separado de cada biblioteca ainda não foi implementado.

Esses números são o tamanho de executar Lua no navegador em vez de gerar JavaScript, pagos uma vez por versão, depois que a página já está visível. Lunar não comprime por conta própria, porque isso exigiria DEFLATE em Lua; serve o arquivo `.br` ou `.gz` ao lado do original, e um proxy ou uma borda na frente fazem o mesmo.

:::note
Uma aplicação congelada para Cloudflare Workers ocupa cerca de 143 KB, e a plataforma comprime o que entrega.
:::
