---
slug: instalacao
group: Começar
title: Primeiros passos
description: Como instalar o Lunar e rodar o primeiro exemplo.
---

## Instale o Lunar {#instale}

Você vai precisar de Lua 5.4. O instalador oficial joga os arquivos numa pasta do seu usuário e não pede root. Vale ler o [script](https://lunar.estelaz.com/install.sh) antes de rodar.

```
curl --proto '=https' --tlsv1.2 -sSf https://lunar.estelaz.com/install.sh | sh
```

A release mais nova cai em `~/.lunar`, e o comando `lunar` em `~/.local/bin`. Se a máquina não tiver Lua 5.4, use `--with-lua` para o instalador baixar o interpretador e o LuaSocket. Outra revisão: `--ref` com tag, branch ou commit.

## Rode o exemplo {#rode-o-exemplo}

```
lunar dev "$HOME/.lunar/examples/tranquility"
```

Abra `http://localhost:3000`. O servidor gera o que for pedido e recarrega quando um arquivo muda.

## Crie sua aplicação {#crie-sua-aplicacao}

Uma aplicação é um diretório com `orbit/` dentro. Dá para começar com uma página só:

```orbit/page.lunar
<script>
  count = 0
</script>

<h1>Olá, Lunar.</h1>
<button on:click={function() count = count + 1 end}>
  Cliques: {count}
</button>

<style>
  h1 { color: #546dff; }
</style>
```

```
lunar dev meu-app
```

O HTML já chega renderizado. O navegador só assume os cliques.

## Ou a partir de um clone {#de-um-clone}

```
git clone https://github.com/Glazastyy/Lunar.git
cd Lunar
bin/lunar dev examples/tranquility
```

:::note
LuaSocket só entra para servir. Compilar, inspecionar e empacotar rodam num Lua 5.4 puro.
:::
