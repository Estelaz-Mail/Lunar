---
slug: componentes
group: Escrever
title: Componentes
description: Como montar um arquivo .lunar com script, marcação e estilo.
---

Um arquivo `.lunar` tem três pedaços, e nenhum é obrigatório: um `<script>`, a marcação e um `<style>`.

```lib/Cartao.lunar
<script>
  props { title = "sem título" }
  aberto = false
</script>

<article>
  <h2>{title}</h2>
  <button on:click={function() aberto = not aberto end}>
    {aberto and "fechar" or "abrir"}
  </button>
  {#if aberto}
    <div class="corpo"><slot /></div>
  {/if}
</article>

<style>
  .corpo { padding: 1rem; }
</style>
```

## Propriedades {#propriedades}

`props { nome = padrão }` é o que o componente aceita de fora. Se ninguém passar nada, vale o padrão. Dentro do arquivo você lê isso como variável normal.

```
<Cartao title="Relatório" />
<Cartao title={data.titulo} />
```

## Importar outro componente {#importar}

```
<script>
  local Cartao = import("/lib/Cartao.lunar")
</script>

<Cartao title="Olá" />
```

Nome de componente começa com maiúscula. Barra no começo do caminho sai da raiz da aplicação. Sem barra, sai do arquivo atual.

## Slots {#slots}

O que o pai escreve por dentro cai no `<slot />`. Se o slot já tiver um texto, esse texto aparece quando o pai não mandou nada.

```lib/Painel.lunar
<header><slot name="topo" /></header>
<div><slot>nada por aqui</slot></div>
<footer><slot name="rodape">sem rodapé</slot></footer>
```

```orbit/page.lunar
<Painel>
  <h2 slot="topo">Título</h2>
  <p>O corpo do painel.</p>
</Painel>
```

`<slot name="..." />` pega os filhos com o atributo `slot` do mesmo nome. O resto vai para o slot sem nome. Esse atributo não sai no HTML.

## Estilos com escopo {#estilos}

O CSS do arquivo ganha uma classe do compilador e só pega os elementos dali. `:global(...)` é a porta de saída, se você quiser.

```
<style>
  .corpo { padding: 1rem; }
  :global(body) { margin: 0; }
</style>
```

## Metadados da página {#metadados}

```
<lunar:head>
  <title>Meu projeto</title>
  <meta name="description" content="Minha página em Lua." />
</lunar:head>
```

:::note
Erro no `<script>` aponta a linha do `.lunar`, não a do Lua gerado. A numeração é a do arquivo que você editou.
:::
