---
slug: cli
group: Ir além
title: Linha de comando
description: Os comandos do lunar e o que cada um faz.
---

| Comando                    | O que faz                                             |
| -------------------------- | ----------------------------------------------------- |
| `lunar dev [app]`          | sobe o servidor compilando sob demanda e recarregando |
| `lunar build [app]`        | compila tudo uma vez e reporta o que falhou           |
| `lunar map [app]`          | imprime a tabela de rotas como ela foi descoberta     |
| `lunar compile <arquivo>`  | escreve na saída o Lua gerado para um componente      |
| `lunar wasm <arquivos>`    | compila funções Lua em partes WebAssembly             |
| `lunar bench [app]`        | mede compilação, renderização, hidratação e download  |
| `lunar bench --http <url>` | mede um servidor em pé por conexões keep-alive        |
| `lunar workers [app]`      | gera a pasta de deploy para Cloudflare Workers        |
| `lunar spec [nome...]`     | roda a suíte do framework                             |

## Ambiente {#ambiente}

`HOST` e `PORT` escolhem onde servir, `RATE_LIMIT=0` desliga o limitador para um teste de carga, e `WASM_OUT` indica o diretório de saída do `lunar wasm`.

## lunar.json {#manifesto}

```lunar.json
{
  "name": "Meu app",
  "description": "O que ele é.",
  "lang": "pt-BR",
  "port": 3000
}
```

O manifesto na raiz da aplicação nomeia o projeto e ajusta o que o servidor precisa. `lunar.app(options)` aceita as mesmas opções diretamente, além de `client`, `dev`, `minify`, `stylesheets`, `security` e `rate_limit`.

## Versões {#versoes}

O número é lido como o do Lua: `1.0` é a série e o último número é a release dentro dela. Uma mudança no que um componente ou uma aplicação significam sobe a série, do mesmo modo que 5.3 e 5.4 são linguagens diferentes, não só compilação diferente.
