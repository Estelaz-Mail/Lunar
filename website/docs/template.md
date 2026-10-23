---
slug: template
group: Escrever
title: Sintaxe do template
description: Expressões, if, listas, atributos e diretivas da marcação.
---

## Expressões {#expressoes}

O que fica entre chaves é uma expressão Lua, e o resultado é inserido no HTML já escapado. `{@html}` insere marcação sem escapar; a sintaxe é distinta para o ponto de uso deixar isso explícito.

```
<p>{usuario.nome}</p>
<p>{total > 0 and "sim" or "não"}</p>
<p>{@html corpo_confiavel}</p>
<p>Uma chave literal: \{ </p>
```

:::warn
Não passe por `{@html}` conteúdo que veio de fora.
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

A variável de índice é opcional, e o bloco `{:else}` cobre a lista vazia.

### Listas com chave

A iteração pode nomear a chave que identifica cada linha entre uma atualização e outra.

```
{#each tarefas as tarefa (tarefa.id)}
  <li>{tarefa.titulo}</li>
{/each}
```

Com chave, o runtime compara a lista nova com as linhas já montadas: mantém a linha cuja chave e cujo item continuam os mesmos, remove as que sumiram, cria as que apareceram e reordena o mínimo necessário. Uma linha mantida conserva seus elementos, o estado dos componentes internos e o estado do navegador neles, como foco, valor digitado e reprodução de mídia.

:::note
A linha é reconstruída quando o item deixa de ser o mesmo valor. O bloco com chave se atualiza pelo estado que as linhas leem, não pela mutação interna dos objetos. Duas linhas com a mesma chave são um erro.
:::

## Atributos {#atributos}

```
<img src={caminho} alt="" />
<a href={"/post/" .. slug} class="item {extra}">{titulo}</a>
<div {...atributos} id="fixo"></div>
<input disabled />
```

Um atributo pode receber uma expressão, uma string com interpolação ou nada. `{...tabela}` espalha as chaves da tabela como atributos.

## Diretivas {#diretivas}

| Diretiva                | O que faz                                                      |
| ----------------------- | -------------------------------------------------------------- |
| `on:click={fn}`         | registra um evento                                             |
| `on:submit              | prevent={fn}`                                                  | com modificadores: `prevent`, `stop`, `once`, `self`, `capture`, `passive`, `trusted` |
| `class:ativo={cond}`    | aplica uma classe conforme uma condição                        |
| `style:color={valor}`   | define uma propriedade de estilo                               |
| `bind:value={nome}`     | liga o valor de um campo ao estado, nos dois sentidos          |
| `wasm:preload={"area"}` | inicia o carregamento de uma parte WebAssembly antes do clique |

```
<form on:submit|prevent={enviar}>
  <input bind:value={nome} />
  <input type="checkbox" bind:checked={aceito} />
  <button class:pronto={aceito and nome ~= ""}>Enviar</button>
</form>
```

## Elementos especiais {#elementos-especiais}

- `<slot />` e `<slot name="x" />` recebem o conteúdo escrito pelo pai.
- `<lunar:head>` envia o conteúdo para a `<head>` do documento.
- Um componente é um nome com inicial maiúscula: `<Cartao />`.

:::note
Toda expressão do template é verificada na compilação. Um erro de digitação produz erro com arquivo e linha, em vez de falhar só em execução.
:::
