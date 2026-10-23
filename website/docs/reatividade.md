---
slug: reatividade
group: Escrever
title: Reatividade
description: Como o estado do componente atualiza a tela.
---

No `<script>` de um componente, atribuição comum atualiza a tela. Lunar roda esse script com `_ENV` no escopo do componente, então `conta = conta + 1` mexe no que o template lê de `conta`. `local` continua Lua puro, sem isso.

```
<script>
  conta = 0
  local passo = 2

  local function somar()
    conta = conta + passo
  end
</script>

<button on:click={somar}>{conta}</button>
```

## Efeitos e derivados {#efeitos-e-derivados}

```
<script>
  props { inicio = 0 }
  conta = inicio

  derived("dobro", function() return conta * 2 end)

  watch(function()
    print("conta agora é " .. conta)
  end)
</script>

<p>{conta} — {dobro}</p>
```

`derived(nome, fn)` guarda um valor calculado. `watch(fn)` dispara um efeito. Nos dois, a dependência é o que a última execução leu. Não tem lista para declarar.

## Entrar e sair {#ciclo-de-vida}

```
<script>
  on_rise(function()
    local timer = iniciar()
    return function() parar(timer) end
  end)

  on_set(function()
    print("saindo")
  end)
</script>
```

`on_rise` roda quando o componente entra no documento. Se devolver uma função, essa função roda na saída. `on_set` roda antes de sair.

## Contexto {#contexto}

```
<script>
  set_context("tema", "noite")
</script>
```

```
<script>
  local tema = get_context("tema")
</script>
```

`set_context` e `get_context` passam valor para os filhos sem ficar empurrando propriedade em todo mundo.

## Bindings {#bindings}

```
<script>
  nome = ""
  aceito = false
</script>

<input bind:value={nome} />
<input type="checkbox" bind:checked={aceito} />
<p>Olá, {nome}.</p>
```

:::note
O estado mora no componente que declarou a variável. `bind:` no filho escreve no pai que passou a propriedade. Os dois acompanham.
:::
