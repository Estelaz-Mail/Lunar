---
slug: reatividade
group: Escrever
title: Reatividade
description: Como o estado do componente atualiza a tela.
---

Atribuições no `<script>` de um componente são reativas por padrão. Lunar executa o script com `_ENV` ligado ao escopo do componente, de modo que `conta = conta + 1` atualiza as partes do template que dependem de `conta`. Variáveis declaradas com `local` continuam sendo variáveis Lua comuns.

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

`derived(nome, fn)` mantém um valor calculado e `watch(fn)` executa um efeito. Em ambos, as dependências são o que a última execução leu; não há lista para declarar.

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

`on_rise` é chamado quando o componente entra no documento; se a função devolver outra, essa outra corre na saída. `on_set` é chamado antes da remoção.

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

`set_context` e `get_context` compartilham um valor com os descendentes, sem encaminhar a propriedade por cada nível.

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
O estado permanece no componente que declarou a variável. Um `bind:` no filho escreve no estado do pai que passou a propriedade, e os dois templates acompanham o valor.
:::
