---
slug: introducao
group: Começar
title: Conheça o Lunar
description: O que é o Lunar e como as pastas da aplicação se organizam.
---

Lunar é um framework web em Lua 5.4. Um arquivo `.lunar` contém a marcação, o script e, se houver, o CSS do componente; o servidor renderiza esse arquivo e o navegador hidrata o HTML resultante.

Os `.lunar` são compilados em memória quando a rota precisa deles, e o resultado fica em cache. O servidor HTTP usa LuaSocket; o restante do código da aplicação é Lua.

## O que já funciona {#o-que-ja-funciona}

- Componentes reativos, com propriedades, efeitos e valores derivados.
- Template com `if`, listas (com ou sem chave), bindings e slots.
- CSS restrito ao componente.
- Renderização no servidor e hidratação no navegador, reusando o HTML já enviado.
- Rotas por pasta, com layouts, probes e endpoints HTTP.
- Funções Lua compiladas para WebAssembly, carregadas na primeira chamada.
- Empacotamento para Cloudflare Workers.

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

As páginas ficam em `orbit/`, os componentes compartilhados em `lib/`, as funções destinadas a WebAssembly em `wasm/` e os arquivos públicos em `static/`.

## O vocabulário {#o-vocabulario}

Alguns identificadores são específicos do Lunar:

| Nome      | O que é                                                         |
| --------- | --------------------------------------------------------------- |
| `orbit/`  | a pasta de rotas: um diretório corresponde a uma URL            |
| `page`    | o que aquela URL desenha                                        |
| `shell`   | o layout em volta das páginas, em torno de um `<slot />`        |
| `probe`   | a função que busca os dados da página no servidor               |
| `api`     | um endpoint HTTP                                                |
| `eclipse` | o que aparece quando algo falha, ou quando o caminho não existe |
| moonlight | o pacote que o navegador baixa para executar a aplicação        |
| `on_rise` | o componente acabou de entrar no documento                      |
| `on_set`  | o componente está saindo                                        |
| congelado | a aplicação empacotada para um ambiente sem sistema de arquivos |

:::note
Lunar está na versão 1.0. Ainda não existem blocos `{#await}`, form actions prontas nem páginas em streaming: o runtime não espera uma Promise, e a `<head>` só fica completa quando o corpo termina. Formulários no servidor passam por um `api.lua`. Um endpoint pode responder em pedaços.
:::

A [instalação](/docs/instalacao) está na página seguinte. O código fica no [GitHub](https://github.com/Estelaz-Mail/Lunar).
