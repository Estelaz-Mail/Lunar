return {
  probe = function()
    return {
      title = "Lunar — O framework web em Lua",
      description = "Crie para a web com Lua. Componentes reativos, renderização no servidor e rotas por arquivos. Conheça o Lunar, um framework de código aberto.",
      canonical = "/",
      sources = {
        counter = [=[<script>
  count = 0
</script>

<button on:click={function()
  count = count + 1
end}>
  Cliques: {count}
</button>]=],
        binding = [=[<script>
  name = "Lua"
</script>

<input bind:value={name} />
<p>Olá, {name}.</p>]=],
        condition = [=[<script>
  visible = true
</script>

<button on:click={function()
  visible = not visible
end}>Alternar</button>

{#if visible}
  <p>Menos código.
     Mais possibilidades. ✦</p>
{/if}]=],
      },
    }
  end,
}
