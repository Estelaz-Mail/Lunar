---
slug: wasm
group: Ir além
title: Lua em WebAssembly
description: Como gerar wasm a partir de funções Lua e chamar de um componente.
---

O diretório `wasm/`, ao lado de `orbit/`, contém arquivos Lua comuns cujas funções são compiladas para WebAssembly. O compilador é escrito em Lua, sem toolchain extra nem binário no repositório: cada parte é compilada em memória e fica em cache, como um componente.

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

Um `function` é exportado pela parte; um `local function` permanece interno.

## O que o subconjunto cobre {#subconjunto}

- Aritmética com `+ - * / // % ^`, comparações, `and`, `or`, `not`.
- `if`, `while`, `for` numérico com passo literal, `break`, `local`, atribuição.
- Strings com `..`, `#`, `==` e ordenação byte a byte.
- Tabelas, construtores, `t[k]`, `t.k`, `#t`, `setmetatable`, `getmetatable`, `rawget`, `rawset`, `type`.
- Funções como valor, closures, vários retornos e um `...` final.
- `math.abs`, `math.ceil`, `math.floor`, `math.max`, `math.min`, `math.sqrt`, `math.trunc`.

`//` e `%` arredondam como no Lua, então `-7 % 3` é `2`. Corrotinas, métodos com `:`, `goto` e o restante da biblioteca padrão são recusados na compilação, com arquivo e linha.

## Como os valores são guardados {#valores}

Todo valor é um `f64`, porque um número de Lua já é um. Os demais usam os NaN silenciosos que um double não emprega: uma etiqueta e um endereço na memória. Aritmética não tem custo extra, e `if v then` é falso exatamente para `nil` e `false`.

Strings são bytes na memória, com o tamanho na frente; um literal vai para a seção de dados do módulo, de modo que lê-lo não aloca. Uma tabela tem parte array para as chaves `1..n` e parte hash para o resto. Um número concatenado numa string é escrito como o Lua escreve, com quatorze dígitos significativos; sem subtipo inteiro, `3` sai `3` e não `3.0`.

## A memória, e o que fazer sem coletor {#memoria}

:::warn
Não há coletor de lixo. O alocador avança um ponteiro e não o recua sozinho.
:::

No lugar dele há uma arena explícita: `heap.mark()` lê o ponteiro e `heap.release(marca)` o devolve, liberando de uma vez o que foi alocado no intervalo. Nada alocado depois da marca pode ser retido depois do release.

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

Cada arquivo é uma parte, buscada apenas quando alguma chamada a referencia. Uma parte que usa uma função exportada por outra a importa pelo nome, o que torna a dependência efetiva.

```
$ lunar wasm wasm/*.lua
runtime.wasm      10340 bytes  exports alloc closure_new concat ...
geometria.wasm      171 bytes  exports area hypotenuse
texto.wasm         1014 bytes  exports label summary  needs geometria runtime
```

O servidor compila as partes sob demanda e as serve em `/_lunar/wasm/`, com um `index.json` que lista exportações e dependências. Uma aplicação congelada para Workers grava os mesmos arquivos em `public/`; o WebAssembly é compilado no navegador, não no Worker, de modo que os dois alvos recebem os mesmos bytes.

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

`wasm(nome, pronto)` solicita uma função e a entrega quando a parte chegou. O carregamento é uma busca na rede, então a resposta vem num callback, e a página no servidor renderiza sem isso. O valor retornado já vem convertido: número, `nil`, booleano ou string.

`wasm:preload={"area"}` inicia o carregamento da parte antes do clique, no pointerenter, no foco ou no toque, uma vez só. A diretiva não produz markup.

:::note
Uma função que recebe `...` não pode ser exportada por uma parte, porque a chamada externa não tem como passar os extras: deixe-a `local` e exporte outra que a chame. As partes compiladas pelo Lunar não suportam corrotinas. Elas continuam disponíveis na VM Lua 5.4 do navegador, que também é executada em WebAssembly e pode chamar essas partes.
:::
