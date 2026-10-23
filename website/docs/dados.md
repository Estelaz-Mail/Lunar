---
slug: dados
group: Aplicação
title: Dados e endpoints
description: Como o probe busca dados e como o api.lua responde HTTP.
---

## O probe de uma página {#probe}

`page.lua` ao lado do `page.lunar` busca os dados da rota antes de desenhar. O retorno chega no componente como `data`.

```orbit/blog/[slug]/page.lua
local posts = require("lib.posts")

return {
  probe = function(event)
    local post = posts.get(event.params.slug)
    if not post then
      event.fail(404, "Post não encontrado")
    end
    return { title = post.title, post = post }
  end,
}
```

```orbit/blog/[slug]/page.lunar
<script>
  props { data = {} }
</script>

<h1>{data.post.title}</h1>
```

## O que o probe recebe {#o-evento}

| Campo                             | O que é                                  |
| --------------------------------- | ---------------------------------------- |
| `event.params`                    | os segmentos dinâmicos da rota           |
| `event.query`                     | a query string já separada               |
| `event.request`                   | o pedido, com método, cabeçalhos e corpo |
| `event.fail(status, mensagem)`    | desenha o `eclipse` mais próximo         |
| `event.redirect(status, destino)` | responde com um redirecionamento         |

`fail` e `redirect` param na hora, mesmo chamados de uma função auxiliar.

:::warn
O probe roda no servidor e também quando o navegador navega. Os dados têm que bater. Árvore diferente da que o servidor mandou faz o runtime refazer aquele trecho, em vez de reaproveitar o HTML.
:::

## Endpoints {#endpoints}

`api.lua` responde a uma URL direto, sem página.

```orbit/api/notas/api.lua
return {
  get = function(event)
    return { ok = true, agora = os.time() }
  end,

  post = function(event)
    local corpo = event.request:json()
    if type(corpo) ~= "table" then
      event.fail(400, "esperava JSON")
    end
    salvar(corpo)
    return { status = 201, body = "" }
  end,
}
```

Tabela vira JSON. String vira HTML. Tabela com `status`, `headers` ou `body` o Lunar usa como está.

## Formulários {#formularios}

Não tem form action embutida. O form aponta para um endpoint. O endpoint responde com redirecionamento ou JSON. Sem JavaScript isso continua de pé, porque é HTTP.

```
<form method="post" action="/api/notas">
  <input name="texto" />
  <button>Salvar</button>
</form>
```

## Respostas em pedaços {#streaming}

O endpoint pode ir escrevendo, sem juntar tudo na memória.

```orbit/api/relatorio/api.lua
local response = require("lunar.http.response")

return {
  get = function(event)
    return response.stream(function(write)
      for _, linha in ipairs(relatorio()) do
        write(linha .. "\n")
      end
    end, 200, { ["Content-Type"] = "text/plain; charset=utf-8" })
  end,
}
```

A resposta sai `Transfer-Encoding: chunked`. Cada `write` é um pedaço. Se o socket encher, quem escreve cede a vez: leitor lento segura uma corrotina, não o laço inteiro.

:::note
Se o produtor falhar no meio, o que já saiu não volta. A conexão cai sem o pedaço final, e o cliente entende que o texto veio incompleto. HTTP/1.0 recebe os mesmos bytes juntos, com `Content-Length`. No pacote para Workers, o stream vira uma resposta só.
:::

Página não vai assim. `<lunar:head>` é juntado enquanto o corpo renderiza, então a `<head>` só fica pronta no fim.
