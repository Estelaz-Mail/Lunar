---
slug: dados
group: Aplicação
title: Dados e endpoints
description: Como o probe busca dados e como o api.lua responde HTTP.
---

## O probe de uma página {#probe}

Um `page.lua` ao lado do `page.lunar` obtém os dados da rota antes da renderização. O valor de retorno chega ao componente como `data`.

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
| `event.fail(status, mensagem)`    | renderiza o `eclipse` mais próximo       |
| `event.redirect(status, destino)` | responde com um redirecionamento         |

`fail` e `redirect` interrompem a execução imediatamente, inclusive quando chamados de uma função auxiliar.

:::warn
O probe corre no servidor e também quando o navegador navega para a rota. Ele precisa produzir os mesmos dados para o mesmo estado: uma árvore diferente da que o servidor enviou faz o runtime reconstruir aquele trecho, em vez de reusar o HTML.
:::

## Endpoints {#endpoints}

Um `api.lua` responde a uma URL diretamente, sem página.

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

Uma tabela devolvida vira JSON; uma string vira HTML; uma tabela com `status`, `headers` ou `body` é usada como está.

## Formulários {#formularios}

Não há form actions integradas. O formulário aponta para um endpoint, e o endpoint responde com redirecionamento ou JSON. O caminho continua funcionando sem JavaScript, porque é HTTP comum.

```
<form method="post" action="/api/notas">
  <input name="texto" />
  <button>Salvar</button>
</form>
```

## Respostas em pedaços {#streaming}

Um endpoint pode escrever a resposta aos poucos, sem montar o corpo inteiro na memória.

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

A resposta usa `Transfer-Encoding: chunked`, um pedaço por `write`. Se o socket encher, o escritor cede a vez, de modo que um leitor lento ocupa uma corrotina e não o laço inteiro.

:::note
Se o produtor falhar no meio, o corpo já enviado não pode ser desfeito: a conexão cai sem o pedaço final, o que indica ao cliente que o texto está incompleto. Um cliente HTTP/1.0 recebe os mesmos bytes juntos, com `Content-Length`. Numa aplicação congelada para Workers, o stream é recolhido numa resposta só.
:::

Páginas não são transmitidas assim: o `<lunar:head>` é coletado enquanto o corpo renderiza, então a `<head>` só é conhecida no fim.
