---
slug: renderizacao
group: Aplicação
title: Renderização e hidratação
description: Como o HTML do servidor vira a tela no navegador.
---

## Um componente, dois destinos {#dois-destinos}

Do mesmo arquivo o compilador tira duas funções Lua. Uma escreve HTML no servidor. A outra monta a interface no navegador. A suíte compara as duas saídas byte a byte. Se divergir, é bug.

## O primeiro carregamento {#primeiro-carregamento}

O servidor acha a rota, roda os probes e desenha a página. Os dados vão num bloco `application/json`, que o navegador não executa. O conteúdo aparece antes de qualquer Lua no cliente.

## Fengari e moonlight {#moonlight}

Fengari é Lua no navegador. Moonlight é o pacote da aplicação no cliente: componente, estado e DOM no mesmo arquivo.

## A tomada de controle {#hidratacao}

Na hora de assumir, o runtime não joga o HTML fora. Percorre o template, casa cada nó com o que já está no documento, pendura evento e efeito, e só escreve o que mudou. Elemento continua o mesmo: foco, texto digitado, imagem já carregada.

Se a árvore não bater, ele não remenda. Avisa a diferença e refaz aquele container.

## Atualizações {#atualizacoes}

Texto e atributo são escritos direto. Não tem DOM virtual. `if` e lista sem chave desenham de novo quando o que eles leem muda. Lista com chave é reconciliada: linha que fica guarda os nós, e só o mínimo se move.

## O que o navegador baixa {#custo}

| Peça                        | Sem compressão | Com gzip |
| --------------------------- | -------------- | -------- |
| Fengari                     | 219 KB         | 68 KB    |
| Pacote moonlight do exemplo | 88 KB          | 18 KB    |

Esse é o preço de rodar Lua no navegador em vez de gerar JavaScript. Paga uma vez por versão, depois que a página já está visível. Lunar não comprime sozinho (isso pediria DEFLATE em Lua). Ele serve o `.br` ou `.gz` que estiver ao lado. Proxy ou borda na frente fazem o mesmo.

:::note
Aplicação congelada para Cloudflare Workers fica por volta de 143 KB. A plataforma comprime o que entrega.
:::
