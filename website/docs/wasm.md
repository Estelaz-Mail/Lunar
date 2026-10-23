---
slug: wasm
group: Ir além
title: Lua em WebAssembly
description: Como gerar wasm a partir de funções Lua e chamar de um componente.
---

A pasta `wasm/`, ao lado de `orbit/`, guarda Lua comum. Essas funções viram WebAssembly. O compilador é Lua: sem toolchain extra, sem binário no repo, sem etapa de build. A parte nasce em memória e fica em cache, igual componente.

```wasm/geometria.lua
function area(raio)
  return 3.141592653589793 * raio ^ 2
end

local function termo(indice)
  return 1 / (indice * indice)
end

function basileia(quantidade)
  local total = 0
  for indice = 1, quantidade do
    total = total + termo(indice)
  end
  return total
end
```

`function` é exportado pela parte. `local function` fica só dentro.

## O que o subconjunto cobre {#subconjunto}

- Aritmética com `+ - * / // % ^`, comparações, `and`, `or`, `not`.
- `if`, `while`, `for` numérico com passo literal, `break`, `local`, atribuição.
- Strings com `..`, `#`, `==` e ordenação byte a byte.
- Tabelas, construtores, `t[k]`, `t.k`, `#t`, `setmetatable`, `getmetatable`, `rawget`, `rawset`, `type`.
- Função como valor, closure, vários retornos e `...` no fim.
- `math.abs`, `math.ceil`, `math.floor`, `math.max`, `math.min`, `math.sqrt`, `math.trunc`.

`//` e `%` arredondam como no Lua, então `-7 % 3` é `2`. Corrotina, método com `:`, `goto` e o resto da biblioteca padrão caem na compilação, com arquivo e linha.

## Como os valores são guardados {#valores}

Todo valor é um `f64`, porque número em Lua já é isso. O resto viaja nos NaN que um double não usa: etiqueta e endereço. Conta não paga extra. `if v then` é falso só para `nil` e `false`.

String é bytes com o tamanho na frente. Literal vai para a seção de dados, então ler não aloca. Tabela tem array para `1..n` e hash para o resto. Número colado em string sai como o Lua escreve, quatorze dígitos. Sem subtipo inteiro, `3` sai `3`, não `3.0`.

## A memória, e o que fazer sem coletor {#memoria}

:::warn
Não tem coletor de lixo. O alocador empurra um ponteiro e não traz sozinho.
:::

No lugar tem arena: `heap.mark()` lê o ponteiro e `heap.release(marca)` devolve, soltando o que foi alocado no meio. Nada alocado depois da marca pode viver depois do release.

```
function moer(rodadas)
  local ultima = 0
  local rodada = 1
  while rodada <= rodadas do
    local marca = heap.mark()
    local rascunho = { rodada }
    ultima = rascunho[1]
    heap.release(marca)
    rodada = rodada + 1
  end
  return ultima
end
```

## Partes carregadas sob demanda {#partes}

Cada arquivo é uma parte. Só baixa quando alguém chama uma função dela. Se uma parte chama função de outra, importa pelo nome. A dependência fica de verdade, não só no papel.

```
$ lunar wasm wasm/*.lua
runtime.wasm      10340 bytes  exports alloc closure_new concat ...
geometria.wasm      171 bytes  exports area hypotenuse
texto.wasm         1014 bytes  exports label summary  needs geometria runtime
```

O servidor gera as partes sob demanda e serve em `/_lunar/wasm/`, com um `index.json` de quem exporta o quê. Pacote para Workers escreve os mesmos arquivos em `public/`. Quem monta o WebAssembly é o navegador, não o Worker. Os dois alvos baixam os mesmos bytes.

## Usar de um componente {#no-componente}

```
<script>
  area_de = nil

  local function medir()
    wasm("area", function(area) area_de = area(3) end)
  end
</script>

<button wasm:preload={"area"} on:click={medir}>medir</button>
<output>{area_de or "—"}</output>
```

`wasm(nome, pronto)` pede a função e entrega quando a parte chegou. É busca na rede, então a resposta vem no callback. A página no servidor desenha sem isso. O que volta já vem lido: número, `nil`, booleano, string.

`wasm:preload={"area"}` pede a parte antes do clique (ponteiro, foco ou toque), uma vez só. Não desenha nada.

:::note
Função com `...` não exporta: de fora não tem como passar o resto. Deixe `local` e exporte outra que a chama. Corrotina não existe no wasm. Isso fica no Lua do Fengari, que pode chamar a parte.
:::
