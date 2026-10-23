---
slug: rotas
group: Aplicação
title: Rotas
description: Como as pastas em orbit correspondem a URLs.
---

O diretório `orbit/` define as rotas: cada pasta corresponde a um segmento da URL.

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

- `[nome]` corresponde a um segmento e fica em `event.params.nome`.
- `[...nome]` captura os segmentos restantes.
- `(grupo)` organiza arquivos sem entrar na URL.

A correspondência prefere o segmento literal, depois o parâmetro, depois o que captura o resto.

## Layouts {#shell}

```orbit/shell.lunar
<script>
  props { data = {} }
  local Nav = import("/lib/Nav.lunar")
</script>

<header><Nav links={data.links or {}} /></header>
<main><slot /></main>
```

O conteúdo da página é inserido no `<slot />` do shell, e os dados do `shell.lua` se juntam aos da página em `data`.

## Navegação {#navegacao}

Um link entre rotas da aplicação carrega os dados e substitui a página sem recarregar o documento. Uma visita direta à mesma URL continua recebendo HTML renderizado no servidor.

## Arquivos públicos {#estaticos}

O conteúdo de `static/` é servido a partir da raiz do site. Se existir a cópia comprimida e o pedido aceitar a codificação, o servidor envia `app.js.br` para `br` e `app.js.gz` para `gzip`.

:::note
Um `app.html` na raiz da aplicação substitui o documento em volta das páginas.
:::
