---
slug: componentes
group: Escrever
title: Componentes
description: Como montar um arquivo .lunar com script, marcação e estilo.
---

Um arquivo `.lunar` tem três partes, todas opcionais: um `<script>`, a marcação e um `<style>`.

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

`props { nome = padrão }` declara os valores que o componente recebe de fora; se o pai não passar um deles, vale o padrão. Dentro do arquivo, a propriedade se lê como uma variável comum.

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

O nome do componente começa com letra maiúscula. Um caminho iniciado por barra é relativo à raiz da aplicação; um caminho relativo é resolvido a partir do arquivo atual.

## Slots {#slots}

O conteúdo que o pai coloca dentro do componente é inserido no `<slot />`. Se o slot tiver um conteúdo próprio, esse conteúdo é usado quando o pai não preenche o espaço.

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

Cada `<slot name="..." />` recebe os filhos com o atributo `slot` correspondente; o restante vai para o slot sem nome. O atributo `slot` não aparece no HTML gerado.

## Estilos com escopo {#estilos}

O CSS do componente recebe uma classe gerada pelo compilador e só se aplica aos elementos daquele arquivo. `:global(...)` tira um seletor desse escopo.

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
Um erro no `<script>` aponta para a linha do arquivo `.lunar`, não para a do módulo gerado: o compilador preserva a numeração.
:::
