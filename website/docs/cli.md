---
slug: cli
group: Ir além
title: Linha de comando
description: Os comandos do lunar e o que cada um faz.
---

| Comando                    | O que faz                                            |
| -------------------------- | ---------------------------------------------------- |
| `lunar dev [app]`          | sobe o servidor, gera sob demanda e recarrega        |
| `lunar build [app]`        | gera tudo uma vez e mostra o que falhou              |
| `lunar map [app]`          | imprime a tabela de rotas como ela foi descoberta    |
| `lunar compile <arquivo>`  | escreve na saída o Lua gerado para um componente     |
| `lunar wasm <arquivos>`    | gera partes WebAssembly a partir de Lua              |
| `lunar bench [app]`        | mede compilação, renderização, hidratação e download |
| `lunar bench --http <url>` | mede um servidor em pé por conexões keep-alive       |
| `lunar workers [app]`      | gera a pasta de deploy para Cloudflare Workers       |
| `lunar spec [nome...]`     | roda a suíte do framework                            |

## Ambiente {#ambiente}

`HOST` e `PORT` escolhem onde servir. `RATE_LIMIT=0` desliga o limitador para teste de carga. `WASM_OUT` diz onde o `lunar wasm` deve escrever.

## lunar.json {#manifesto}

```lunar.json
{
  "name": "Meu app",
  "description": "O que ele é.",
  "lang": "pt-BR",
  "port": 3000
}
```

O manifesto na raiz nomeia o projeto e ajusta o que o servidor precisa. `lunar.app(options)` aceita as mesmas opções direto, além de `client`, `dev`, `minify`, `stylesheets`, `security` e `rate_limit`.

## Versões {#versoes}

O número é lido como o do Lua. `1.0` é a série; o último número é a release dentro dela. Se mudar o que um componente ou uma aplicação significam, a série sobe. 5.3 e 5.4 são linguagens diferentes, não só compilação diferente.
