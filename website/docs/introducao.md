---
slug: introducao
group: Começar
title: Conheça o Lunar
description: O que é o Lunar e como as pastas da aplicação se organizam.
---

Lunar é um framework web em Lua 5.4. Você escreve um arquivo `.lunar` com HTML, um pouco de Lua e CSS se quiser. O servidor renderiza esse arquivo. No navegador, o mesmo arquivo continua dali, sem a página ser montada outra vez.

Não tem etapa de build. Os componentes saem compilados na hora, em memória, e o resultado fica em cache. Fora o LuaSocket, que só entra para abrir sockets, o resto é Lua.

## O que já funciona {#o-que-ja-funciona}

- Componentes reativos, com propriedades, efeitos e valores derivados.
- Template com `if`, listas (com ou sem chave), bindings e slots.
- CSS que vale só naquele componente.
- HTML no servidor e hidratação no navegador, reaproveitando o que já chegou.
- Rotas por pasta, com layouts, probes e endpoints HTTP.
- Funções Lua em WebAssembly, carregadas quando alguém chama.
- Pacote para Cloudflare Workers.

## Uma estrutura pequena {#uma-estrutura-pequena}

```
meu-app/
  lunar.json
  orbit/
    shell.lunar
    page.lunar
    page.lua
    api/
      hello/
        api.lua
  lib/
  wasm/
  static/
```

Páginas ficam em `orbit/`. Componentes que você reutiliza, em `lib/`. Funções que vão para WebAssembly, em `wasm/`. Arquivo estático, em `static/`.

## O vocabulário {#o-vocabulario}

Alguns nomes o Lunar inventa. Segue o que cada um é.

| Nome      | O que é                                                         |
| --------- | --------------------------------------------------------------- |
| `orbit/`  | a pasta de rotas: um diretório corresponde a uma URL            |
| `page`    | o que aquela URL desenha                                        |
| `shell`   | o layout em volta das páginas, em torno de um `<slot />`        |
| `probe`   | a função que busca os dados da página no servidor               |
| `api`     | um endpoint HTTP                                                |
| `eclipse` | o que aparece quando algo falha, ou quando o caminho não existe |
| moonlight | o pacote que o navegador baixa para rodar a aplicação           |
| `on_rise` | o componente acabou de entrar no documento                      |
| `on_set`  | o componente está saindo                                        |
| congelado | a aplicação empacotada para um ambiente sem sistema de arquivos |

:::note
Lunar está na 1.0. Ainda não tem `{#await}`, form action pronta nem página em streaming. O runtime não espera Promise, e a `<head>` só fica pronta quando o corpo termina. Formulário no servidor vai para um `api.lua`. Endpoint pode responder em pedaços, se você montar assim.
:::

A [instalação](/docs/instalacao) está na página seguinte. O código fica no [GitHub](https://github.com/Glazastyy/Lunar).
