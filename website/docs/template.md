---
slug: template
group: Escrever
title: Sintaxe do template
description: Expressões, if, listas, atributos e diretivas da marcação.
---

## Expressões {#expressoes}

Entre chaves vai Lua. Texto sai escapado. `{@html}` é o jeito de meter marcação crua, e existe separado para o código deixar isso visível.

```
<p>{usuario.nome}</p>
<p>{total > 0 and "sim" or "não"}</p>
<p>{@html corpo_confiavel}</p>
<p>Uma chave literal: \{ </p>
```

:::warn
Não passe por `{@html}` coisa que veio de fora.
:::

## Condicionais {#condicionais}

```
{#if conta > 0}
  <p>Temos cliques.</p>
{:else if conta < 0}
  <p>Abaixo de zero.</p>
{:else}
  <p>Ainda nada.</p>
{/if}
```

## Listas {#listas}

```
{#each itens as item, i}
  <li>{i}: {item.nome}</li>
{:else}
  <li>Nenhum item.</li>
{/each}
```

O índice pode ficar de fora. `{:else}` cobre lista vazia.

### Listas com chave

Dá para dizer qual valor identifica cada linha de uma atualização para a outra.

```
{#each tarefas as tarefa (tarefa.id)}
  <li>{tarefa.titulo}</li>
{/each}
```

Com chave, Lunar olha a lista nova e a que já está na tela. Chave e item iguais: a linha fica. Sumiu: some. Apareceu: cria. O resto ele empurra o mínimo. Linha que ficou guarda elemento, estado de componente e o que o navegador já tinha nela (foco, texto, vídeo).

:::note
Se o item deixa de ser o mesmo valor, a linha nasce de novo. O bloco lê o estado das linhas, não a mutação escondida do objeto. Duas linhas com a mesma chave dão erro.
:::

## Atributos {#atributos}

```
<img src={caminho} alt="" />
<a href={"/post/" .. slug} class="item {extra}">{titulo}</a>
<div {...atributos} id="fixo"></div>
<input disabled />
```

Atributo aceita expressão, string com interpolação, ou nada. `{...tabela}` espalha a tabela inteira.

## Diretivas {#diretivas}

| Diretiva                | O que faz                                               |
| ----------------------- | ------------------------------------------------------- |
| `on:click={fn}`         | escuta um evento                                        |
| `on:submit              | prevent={fn}`                                           | com modificadores: `prevent`, `stop`, `once`, `self`, `capture`, `passive`, `trusted` |
| `class:ativo={cond}`    | liga uma classe a uma condição                          |
| `style:color={valor}`   | escreve uma propriedade de estilo                       |
| `bind:value={nome}`     | liga o valor de um campo ao estado, nos dois sentidos   |
| `wasm:preload={"area"}` | começa a carregar uma parte WebAssembly antes do clique |

```
<form on:submit|prevent={enviar}>
  <input bind:value={nome} />
  <input type="checkbox" bind:checked={aceito} />
  <button class:pronto={aceito and nome ~= ""}>Enviar</button>
</form>
```

## Elementos especiais {#elementos-especiais}

- `<slot />` e `<slot name="x" />` recebem o que o pai escreveu.
- `<lunar:head>` manda o conteúdo para a `<head>` do documento.
- Componente é nome com inicial maiúscula: `<Cartao />`.

:::note
Expressão do template é checada na compilação. Erro de digitação vem com arquivo e linha, não some em produção.
:::
