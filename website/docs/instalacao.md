---
slug: instalacao
group: Começar
title: Primeiros passos
description: Como instalar o Lunar e rodar o primeiro exemplo.
---

## Instale o Lunar {#instale}

É necessário Lua 5.4. O instalador oficial grava os arquivos numa pasta do seu usuário, sem pedir root; leia o [script](https://lunar.estelaz.com/install.sh) antes de executá-lo.

```
curl --proto '=https' --tlsv1.2 -sSf https://lunar.estelaz.com/install.sh | sh
```

A release mais recente fica em `~/.lunar` e o executável `lunar` em `~/.local/bin`. Se a máquina não tiver Lua 5.4, `--with-lua` faz o instalador obter o interpretador e o LuaSocket. Para outra revisão, use `--ref` com uma tag, um branch ou um commit.

## Rode o exemplo {#rode-o-exemplo}

```
lunar dev "$HOME/.lunar/examples/tranquility"
```

Abra `http://localhost:3000`. O servidor compila os componentes conforme a rota e recarrega a página quando um arquivo muda.

## Crie sua aplicação {#crie-sua-aplicacao}

Uma aplicação é um diretório com `orbit/` dentro. O menor caso é uma página só:

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

O HTML chega já renderizado; o navegador associa os eventos ao markup existente.

## Ou a partir de um clone {#de-um-clone}

```
git clone https://github.com/Glazastyy/Lunar.git
cd Lunar
bin/lunar dev examples/tranquility
```

:::note
O LuaSocket só é necessário para servir. Compilar, inspecionar e empacotar funcionam com um Lua 5.4 puro.
:::
