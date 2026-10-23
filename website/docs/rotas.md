---
slug: rotas
group: Aplicação
title: Rotas
description: Como as pastas em orbit viram URL.
---

A pasta `orbit/` é o mapa. Um diretório vira URL.

```
orbit/
  shell.lunar          envolve tudo
  shell.lua            dados compartilhados
  page.lunar           /
  page.lua             dados de /
  sobre/
    page.lunar         /sobre
  blog/
    page.lunar         /blog
    [slug]/
      page.lunar       /blog/qualquer-coisa
      page.lua
  api/
    hello/
      api.lua          /api/hello
  eclipse.lunar        erros e caminhos que não existem
```

| Arquivo         | Papel                                                |
| --------------- | ---------------------------------------------------- |
| `page.lunar`    | o que a URL desenha                                  |
| `page.lua`      | o `probe` que busca os dados daquela página          |
| `shell.lunar`   | envolve as páginas abaixo, em torno de um `<slot />` |
| `shell.lua`     | dados compartilhados por tudo que está abaixo        |
| `api.lua`       | um endpoint HTTP                                     |
| `eclipse.lunar` | o que aparece quando algo falha ou a rota não existe |

## Segmentos dinâmicos {#segmentos}

- `[nome]` pega um pedaço do caminho e chega em `event.params.nome`.
- `[...nome]` pega o resto.
- `(grupo)` só organiza arquivo. Não entra na URL.

Na hora de casar, vale o nome literal, depois o parâmetro, depois o que come o resto.

## Layouts {#shell}

```orbit/shell.lunar
<script>
  props { data = {} }
  local Nav = import("/lib/Nav.lunar")
</script>

<header><Nav links={data.links or {}} /></header>
<main><slot /></main>
```

O conteúdo da página entra no `<slot />` do shell. Dados do `shell.lua` se juntam aos da página em `data`.

## Navegação {#navegacao}

Link interno pede os dados e troca a página sem recarregar o documento. Abrir a URL direto manda o HTML pronto. Mesma rota.

## Arquivos públicos {#estaticos}

O que está em `static/` sai na raiz do site. Se existir o irmão comprimido e o pedido aceitar, vai ele: `app.js.br` para `br`, `app.js.gz` para `gzip`.

:::note
Um `app.html` na raiz troca o documento em volta de tudo isso.
:::
