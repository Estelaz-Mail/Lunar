local pages = {
  { slug = [==[introducao]==], group = [==[Começar]==], title = [==[Conheça o Lunar]==], description = [==[Um framework web em Lua, do primeiro HTML à última interação.]==], body = [==[<p>Lunar é um framework para construir aplicações web com Lua 5.4. Um componente reúne marcação, lógica e estilo em um arquivo <code>.lunar</code>; o mesmo componente é renderizado no servidor e assume o controle no navegador.</p><p>Não há passo de build. Os componentes são compilados em memória, sob demanda, e guardados em cache pelos próprios bytes. Fora o LuaSocket para os sockets, não há dependência nenhuma.</p><h2 id="o-que-ja-funciona"><a class="doc-anchor" href="#o-que-ja-funciona" aria-label="Link para esta seção">#</a>O que já funciona</h2><ul><li>Componentes reativos, com propriedades, efeitos e valores derivados.</li><li>Sintaxe de template com condicionais, listas (com ou sem chave), bindings e slots nomeados.</li><li>CSS com escopo por componente.</li><li>Renderização no servidor e hidratação que reivindica os elementos já entregues.</li><li>Rotas por arquivos, com layouts, probes e endpoints HTTP.</li><li>Funções Lua compiladas para WebAssembly, carregadas sob demanda.</li><li>Empacotamento para Cloudflare Workers.</li></ul><h2 id="uma-estrutura-pequena"><a class="doc-anchor" href="#uma-estrutura-pequena" aria-label="Link para esta seção">#</a>Uma estrutura pequena</h2><figure class="doc-code"><pre><code>meu-app/
  lunar.json
  orbit/
    shell.lunar
    page.lunar
    page.lua
    api/
      hello/
        api.lua
  lib/
  wasm/
  static/</code></pre></figure><p>As páginas ficam em <code>orbit/</code>, os componentes compartilhados em <code>lib/</code>, as funções compiladas para WebAssembly em <code>wasm/</code> e os arquivos públicos em <code>static/</code>.</p><h2 id="o-vocabulario"><a class="doc-anchor" href="#o-vocabulario" aria-label="Link para esta seção">#</a>O vocabulário</h2><p>Lunar tem nomes próprios para as suas partes. Vale conhecê-los antes de seguir.</p><div class="doc-table"><table><thead><tr><th>Nome</th><th>O que é</th></tr></thead><tbody><tr><td><code>orbit/</code></td><td>a árvore de rotas: um diretório é uma URL</td></tr><tr><td><code>page</code></td><td>o que uma URL desenha</td></tr><tr><td><code>shell</code></td><td>o que envolve uma página e tudo abaixo dela, em torno de um <code>&lt;slot /&gt;</code></td></tr><tr><td><code>probe</code></td><td>a função que busca os dados de uma página no servidor</td></tr><tr><td><code>api</code></td><td>um endpoint</td></tr><tr><td><code>eclipse</code></td><td>o que aparece quando a luz se apaga: uma falha, ou um caminho que não existe</td></tr><tr><td>moonlight</td><td>a aplicação como ela chega ao navegador, em um pacote só</td></tr><tr><td><code>on_rise</code></td><td>montado: o componente está no documento</td></tr><tr><td><code>on_set</code></td><td>prestes a sair</td></tr><tr><td>congelado</td><td>uma aplicação empacotada para uma plataforma sem sistema de arquivos</td></tr></tbody></table></div><div class="doc-note">O projeto está na versão 1.0. Blocos <code>{#await}</code>, form actions integradas e páginas em streaming não existem: o runtime não tem primitiva assíncrona para aguardar e uma página só conhece a sua <code>&lt;head&gt;</code> quando o corpo terminou. Formulários no servidor passam por um <code>api.lua</code>, e um endpoint pode, sim, responder em pedaços.</div><p>Comece pela <a href="/docs/instalacao">instalação</a>, ou leia o <a href="https://github.com/Glazastyy/Lunar">código-fonte no GitHub</a>.</p>]==] },
  { slug = [==[instalacao]==], group = [==[Começar]==], title = [==[Primeiros passos]==], description = [==[Do terminal ao seu primeiro componente reativo.]==], body = [==[<h2 id="instale"><a class="doc-anchor" href="#instale" aria-label="Link para esta seção">#</a>Instale o Lunar</h2><p>O instalador oficial usa uma pasta no seu diretório pessoal e não pede root. Leia o <a href="https://lunar.estelaz.com/install.sh">script</a> antes de executá-lo.</p><figure class="doc-code"><pre><code>curl --proto '=https' --tlsv1.2 -sSf https://lunar.estelaz.com/install.sh | sh</code></pre></figure><p>Ele instala a release mais nova em <code>~/.lunar</code> e o launcher em <code>~/.local/bin</code>. Lua 5.4 é necessário; o instalador pode compilá-lo com <code>--with-lua</code> e preparar o LuaSocket quando a sua máquina não tiver um. Para instalar outra revisão, use <code>--ref</code> com uma tag, um branch ou um commit.</p><h2 id="rode-o-exemplo"><a class="doc-anchor" href="#rode-o-exemplo" aria-label="Link para esta seção">#</a>Rode o exemplo</h2><figure class="doc-code"><pre><code>lunar dev "$HOME/.lunar/examples/tranquility"</code></pre></figure><p>Abra <code>http://localhost:3000</code>. O servidor compila os componentes sob demanda e recarrega a página quando um arquivo muda.</p><h2 id="crie-sua-aplicacao"><a class="doc-anchor" href="#crie-sua-aplicacao" aria-label="Link para esta seção">#</a>Crie sua aplicação</h2><p>Uma aplicação é um diretório com uma árvore <code>orbit/</code> dentro. O menor exemplo possível é uma página só:</p><figure class="doc-code"><figcaption>orbit/page.lunar</figcaption><pre><code>&lt;script&gt;
  count = 0
&lt;/script&gt;

&lt;h1&gt;Olá, Lunar.&lt;/h1&gt;
&lt;button on:click={function() count = count + 1 end}&gt;
  Cliques: {count}
&lt;/button&gt;

&lt;style&gt;
  h1 { color: #546dff; }
&lt;/style&gt;</code></pre></figure><figure class="doc-code"><pre><code>lunar dev meu-app</code></pre></figure><p>A página chega pronta do servidor, com o HTML já renderizado, e o navegador assume a interação sem reconstruí-la.</p><h2 id="de-um-clone"><a class="doc-anchor" href="#de-um-clone" aria-label="Link para esta seção">#</a>Ou a partir de um clone</h2><figure class="doc-code"><pre><code>git clone https://github.com/Glazastyy/Lunar.git
cd Lunar
bin/lunar dev examples/tranquility</code></pre></figure><div class="doc-note">O LuaSocket só é necessário para servir. Compilar, inspecionar e empacotar funcionam com um Lua 5.4 puro.</div>]==] },
  { slug = [==[componentes]==], group = [==[Escrever]==], title = [==[Componentes]==], description = [==[Marcação, lógica e estilo no mesmo arquivo.]==], body = [==[<p>Um arquivo <code>.lunar</code> tem três partes, todas opcionais: um <code>&lt;script&gt;</code>, a marcação e um <code>&lt;style&gt;</code>.</p><figure class="doc-code"><figcaption>lib/Cartao.lunar</figcaption><pre><code>&lt;script&gt;
  props { title = "sem título" }
  aberto = false
&lt;/script&gt;

&lt;article&gt;
  &lt;h2&gt;{title}&lt;/h2&gt;
  &lt;button on:click={function() aberto = not aberto end}&gt;
    {aberto and "fechar" or "abrir"}
  &lt;/button&gt;
  {#if aberto}
    &lt;div class="corpo"&gt;&lt;slot /&gt;&lt;/div&gt;
  {/if}
&lt;/article&gt;

&lt;style&gt;
  .corpo { padding: 1rem; }
&lt;/style&gt;</code></pre></figure><h2 id="propriedades"><a class="doc-anchor" href="#propriedades" aria-label="Link para esta seção">#</a>Propriedades</h2><p><code>props { nome = padrão }</code> declara o que o componente aceita de fora, com os valores usados quando nada é passado. Uma propriedade é lida como uma variável comum.</p><figure class="doc-code"><pre><code>&lt;Cartao title="Relatório" /&gt;
&lt;Cartao title={data.titulo} /&gt;</code></pre></figure><h2 id="importar"><a class="doc-anchor" href="#importar" aria-label="Link para esta seção">#</a>Importar outro componente</h2><figure class="doc-code"><pre><code>&lt;script&gt;
  local Cartao = import("/lib/Cartao.lunar")
&lt;/script&gt;

&lt;Cartao title="Olá" /&gt;</code></pre></figure><p>Nomes de componentes começam com letra maiúscula. Um caminho iniciado por barra parte da raiz da aplicação; um caminho relativo parte do arquivo atual.</p><h2 id="slots"><a class="doc-anchor" href="#slots" aria-label="Link para esta seção">#</a>Slots</h2><p>O conteúdo que um pai escreve dentro do componente entra no <code>&lt;slot /&gt;</code>. O que estiver escrito dentro do slot aparece quando ninguém o preencheu.</p><figure class="doc-code"><figcaption>lib/Painel.lunar</figcaption><pre><code>&lt;header&gt;&lt;slot name="topo" /&gt;&lt;/header&gt;
&lt;div&gt;&lt;slot&gt;nada por aqui&lt;/slot&gt;&lt;/div&gt;
&lt;footer&gt;&lt;slot name="rodape"&gt;sem rodapé&lt;/slot&gt;&lt;/footer&gt;</code></pre></figure><figure class="doc-code"><figcaption>orbit/page.lunar</figcaption><pre><code>&lt;Painel&gt;
  &lt;h2 slot="topo"&gt;Título&lt;/h2&gt;
  &lt;p&gt;O corpo do painel.&lt;/p&gt;
&lt;/Painel&gt;</code></pre></figure><p>Cada <code>&lt;slot name="..." /&gt;</code> recebe os filhos marcados com o atributo <code>slot</code> correspondente; o que sobra entra no slot sem nome. O atributo não aparece no HTML gerado.</p><h2 id="estilos"><a class="doc-anchor" href="#estilos" aria-label="Link para esta seção">#</a>Estilos com escopo</h2><p>O CSS de um componente recebe uma classe gerada pelo compilador e só alcança os elementos daquele componente. Use <code>:global(...)</code> para sair do escopo de propósito.</p><figure class="doc-code"><pre><code>&lt;style&gt;
  .corpo { padding: 1rem; }
  :global(body) { margin: 0; }
&lt;/style&gt;</code></pre></figure><h2 id="metadados"><a class="doc-anchor" href="#metadados" aria-label="Link para esta seção">#</a>Metadados da página</h2><figure class="doc-code"><pre><code>&lt;lunar:head&gt;
  &lt;title&gt;Meu projeto&lt;/title&gt;
  &lt;meta name="description" content="Minha página em Lua." /&gt;
&lt;/lunar:head&gt;</code></pre></figure><div class="doc-note">Um erro dentro do <code>&lt;script&gt;</code> aponta para a linha do arquivo <code>.lunar</code>, não para a do módulo gerado: o compilador preserva a numeração.</div>]==] },
  { slug = [==[template]==], group = [==[Escrever]==], title = [==[Sintaxe do template]==], description = [==[Tudo que a marcação de um componente entende.]==], body = [==[<h2 id="expressoes"><a class="doc-anchor" href="#expressoes" aria-label="Link para esta seção">#</a>Expressões</h2><p>Entre chaves vai Lua. O texto é escapado por padrão; <code>{@html}</code> é a única porta para marcação, e existe separada justamente para que o ponto de uso diga o que está fazendo.</p><figure class="doc-code"><pre><code>&lt;p&gt;{usuario.nome}&lt;/p&gt;
&lt;p&gt;{total &gt; 0 and "sim" or "não"}&lt;/p&gt;
&lt;p&gt;{@html corpo_confiavel}&lt;/p&gt;
&lt;p&gt;Uma chave literal: \{ &lt;/p&gt;</code></pre></figure><div class="doc-note warn">Nunca passe conteúdo que veio de fora por <code>{@html}</code>.</div><h2 id="condicionais"><a class="doc-anchor" href="#condicionais" aria-label="Link para esta seção">#</a>Condicionais</h2><figure class="doc-code"><pre><code>{#if conta &gt; 0}
  &lt;p&gt;Temos cliques.&lt;/p&gt;
{:else if conta &lt; 0}
  &lt;p&gt;Abaixo de zero.&lt;/p&gt;
{:else}
  &lt;p&gt;Ainda nada.&lt;/p&gt;
{/if}</code></pre></figure><h2 id="listas"><a class="doc-anchor" href="#listas" aria-label="Link para esta seção">#</a>Listas</h2><figure class="doc-code"><pre><code>{#each itens as item, i}
  &lt;li&gt;{i}: {item.nome}&lt;/li&gt;
{:else}
  &lt;li&gt;Nenhum item.&lt;/li&gt;
{/each}</code></pre></figure><p>A variável do índice é opcional, e o bloco <code>{:else}</code> cobre a lista vazia.</p><h3>Listas com chave</h3><p>Uma iteração pode nomear a chave que identifica cada linha entre uma atualização e outra.</p><figure class="doc-code"><pre><code>{#each tarefas as tarefa (tarefa.id)}
  &lt;li&gt;{tarefa.titulo}&lt;/li&gt;
{/each}</code></pre></figure><p>Com chave, o Lunar compara a nova lista com as linhas que já existem: mantém a linha cuja chave e cujo item continuam os mesmos, remove as que sumiram, cria as que apareceram e move o mínimo necessário para recolocar tudo em ordem. Uma linha mantida conserva seus elementos, o estado dos componentes dentro dela e o que o navegador pendurou neles — o foco, o valor digitado num campo, um vídeo tocando.</p><div class="doc-note">Uma linha é reconstruída quando seu item deixa de ser o mesmo valor. Um bloco com chave se atualiza pelo estado que suas linhas leem, não pela mutação dos itens. Duas linhas com a mesma chave são um erro.</div><h2 id="atributos"><a class="doc-anchor" href="#atributos" aria-label="Link para esta seção">#</a>Atributos</h2><figure class="doc-code"><pre><code>&lt;img src={caminho} alt="" /&gt;
&lt;a href={"/post/" .. slug} class="item {extra}"&gt;{titulo}&lt;/a&gt;
&lt;div {...atributos} id="fixo"&gt;&lt;/div&gt;
&lt;input disabled /&gt;</code></pre></figure><p>Um atributo pode receber uma expressão, uma string com interpolação, ou nada — e uma tabela inteira pode ser espalhada com <code>{...tabela}</code>.</p><h2 id="diretivas"><a class="doc-anchor" href="#diretivas" aria-label="Link para esta seção">#</a>Diretivas</h2><div class="doc-table"><table><thead><tr><th>Diretiva</th><th>O que faz</th></tr></thead><tbody><tr><td><code>on:click={fn}</code></td><td>escuta um evento</td></tr><tr><td><code>on:submit|prevent={fn}</code></td><td>com modificadores: <code>prevent</code>, <code>stop</code>, <code>once</code>, <code>self</code>, <code>capture</code>, <code>passive</code>, <code>trusted</code></td></tr><tr><td><code>class:ativo={cond}</code></td><td>liga uma classe a uma condição</td></tr><tr><td><code>style:color={valor}</code></td><td>escreve uma propriedade de estilo</td></tr><tr><td><code>bind:value={nome}</code></td><td>liga o valor de um campo ao estado, nos dois sentidos</td></tr><tr><td><code>wasm:preload={"area"}</code></td><td>aquece uma parte WebAssembly antes do clique</td></tr></tbody></table></div><figure class="doc-code"><pre><code>&lt;form on:submit|prevent={enviar}&gt;
  &lt;input bind:value={nome} /&gt;
  &lt;input type="checkbox" bind:checked={aceito} /&gt;
  &lt;button class:pronto={aceito and nome ~= ""}&gt;Enviar&lt;/button&gt;
&lt;/form&gt;</code></pre></figure><h2 id="elementos-especiais"><a class="doc-anchor" href="#elementos-especiais" aria-label="Link para esta seção">#</a>Elementos especiais</h2><ul><li><code>&lt;slot /&gt;</code> e <code>&lt;slot name="x" /&gt;</code> recebem o conteúdo que o pai escreveu.</li><li><code>&lt;lunar:head&gt;</code> manda o que está dentro para a <code>&lt;head&gt;</code> do documento.</li><li>Um componente é um nome com inicial maiúscula: <code>&lt;Cartao /&gt;</code>.</li></ul><div class="doc-note">Toda expressão do template é verificada em tempo de compilação. Um erro de digitação vira erro de compilação com arquivo e linha, não um defeito silencioso em produção.</div>]==] },
  { slug = [==[reatividade]==], group = [==[Escrever]==], title = [==[Reatividade]==], description = [==[Mude o valor. A interface acompanha.]==], body = [==[<p>Atribuições no script de um componente são reativas por padrão. O Lunar executa o script com <code>_ENV</code> ligado ao escopo do componente, então <code>conta = conta + 1</code> atualiza as partes do template que dependem de <code>conta</code>. Variáveis declaradas com <code>local</code> continuam sendo variáveis Lua comuns.</p><figure class="doc-code"><pre><code>&lt;script&gt;
  conta = 0
  local passo = 2

  local function somar()
    conta = conta + passo
  end
&lt;/script&gt;

&lt;button on:click={somar}&gt;{conta}&lt;/button&gt;</code></pre></figure><h2 id="efeitos-e-derivados"><a class="doc-anchor" href="#efeitos-e-derivados" aria-label="Link para esta seção">#</a>Efeitos e derivados</h2><figure class="doc-code"><pre><code>&lt;script&gt;
  props { inicio = 0 }
  conta = inicio

  derived("dobro", function() return conta * 2 end)

  watch(function()
    print("conta agora é " .. conta)
  end)
&lt;/script&gt;

&lt;p&gt;{conta} — {dobro}&lt;/p&gt;</code></pre></figure><p><code>derived(nome, fn)</code> mantém um valor calculado, e <code>watch(fn)</code> roda um efeito. Em ambos as dependências são o que a última execução leu: nada é declarado.</p><h2 id="ciclo-de-vida"><a class="doc-anchor" href="#ciclo-de-vida" aria-label="Link para esta seção">#</a>Entrar e sair</h2><figure class="doc-code"><pre><code>&lt;script&gt;
  on_rise(function()
    local timer = iniciar()
    return function() parar(timer) end
  end)

  on_set(function()
    print("saindo")
  end)
&lt;/script&gt;</code></pre></figure><p><code>on_rise</code> roda quando o componente entra no documento, e a função que ele devolver roda na saída. <code>on_set</code> roda antes da remoção.</p><h2 id="contexto"><a class="doc-anchor" href="#contexto" aria-label="Link para esta seção">#</a>Contexto</h2><figure class="doc-code"><pre><code>&lt;script&gt;
  set_context("tema", "noite")
&lt;/script&gt;</code></pre></figure><figure class="doc-code"><pre><code>&lt;script&gt;
  local tema = get_context("tema")
&lt;/script&gt;</code></pre></figure><p>Um componente compartilha valores com seus descendentes por <code>set_context</code> e <code>get_context</code>, sem passar propriedades por toda a árvore.</p><h2 id="bindings"><a class="doc-anchor" href="#bindings" aria-label="Link para esta seção">#</a>Bindings</h2><figure class="doc-code"><pre><code>&lt;script&gt;
  nome = ""
  aceito = false
&lt;/script&gt;

&lt;input bind:value={nome} /&gt;
&lt;input type="checkbox" bind:checked={aceito} /&gt;
&lt;p&gt;Olá, {nome}.&lt;/p&gt;</code></pre></figure><div class="doc-note">O estado vive no componente que o declarou. Um <code>bind:</code> em um filho escreve no estado do pai que passou a propriedade, e a interface dos dois acompanha.</div>]==] },
  { slug = [==[rotas]==], group = [==[Aplicação]==], title = [==[Rotas]==], description = [==[A estrutura de pastas é o mapa da aplicação.]==], body = [==[<p>O diretório <code>orbit/</code> define as rotas. Um diretório é uma URL.</p><figure class="doc-code"><pre><code>orbit/
  shell.lunar          envolve tudo
  shell.lua            dados compartilhados
  page.lunar           /
  page.lua             dados de /
  sobre/
    page.lunar         /sobre
  blog/
    page.lunar         /blog
    [slug]/
      page.lunar       /blog/qualquer-coisa
      page.lua
  api/
    hello/
      api.lua          /api/hello
  eclipse.lunar        erros e caminhos que não existem</code></pre></figure><div class="doc-table"><table><thead><tr><th>Arquivo</th><th>Papel</th></tr></thead><tbody><tr><td><code>page.lunar</code></td><td>o que a URL desenha</td></tr><tr><td><code>page.lua</code></td><td>o <code>probe</code> que busca os dados daquela página</td></tr><tr><td><code>shell.lunar</code></td><td>envolve as páginas abaixo dele, em torno de um <code>&lt;slot /&gt;</code></td></tr><tr><td><code>shell.lua</code></td><td>dados compartilhados por tudo que está abaixo</td></tr><tr><td><code>api.lua</code></td><td>um endpoint HTTP</td></tr><tr><td><code>eclipse.lunar</code></td><td>o que renderiza quando algo falha ou não existe</td></tr></tbody></table></div><h2 id="segmentos"><a class="doc-anchor" href="#segmentos" aria-label="Link para esta seção">#</a>Segmentos dinâmicos</h2><ul><li><code>[nome]</code> corresponde a um segmento e chega em <code>event.params.nome</code>.</li><li><code>[...nome]</code> captura os segmentos restantes.</li><li><code>(grupo)</code> organiza arquivos sem virar parte da URL.</li></ul><p>A correspondência prefere o segmento literal, depois o parâmetro, depois o que captura o resto.</p><h2 id="shell"><a class="doc-anchor" href="#shell" aria-label="Link para esta seção">#</a>Layouts</h2><figure class="doc-code"><figcaption>orbit/shell.lunar</figcaption><pre><code>&lt;script&gt;
  props { data = {} }
  local Nav = import("/lib/Nav.lunar")
&lt;/script&gt;

&lt;header&gt;&lt;Nav links={data.links or {}} /&gt;&lt;/header&gt;
&lt;main&gt;&lt;slot /&gt;&lt;/main&gt;</code></pre></figure><p>O conteúdo da página entra no <code>&lt;slot /&gt;</code> do shell, e os dados do <code>shell.lua</code> se juntam aos da página em <code>data</code>.</p><h2 id="navegacao"><a class="doc-anchor" href="#navegacao" aria-label="Link para esta seção">#</a>Navegação</h2><p>Links entre rotas da aplicação carregam os dados e trocam a página sem recarregar o documento. Uma visita direta à mesma URL continua funcionando com HTML renderizado no servidor — é a mesma rota, servida dos dois jeitos.</p><h2 id="estaticos"><a class="doc-anchor" href="#estaticos" aria-label="Link para esta seção">#</a>Arquivos públicos</h2><p>O que está em <code>static/</code> é servido a partir da raiz do site. O servidor entrega o irmão comprimido quando ele existe e o pedido aceita: <code>app.js.br</code> para <code>br</code>, <code>app.js.gz</code> para <code>gzip</code>.</p><div class="doc-note">Um <code>app.html</code> na raiz da aplicação personaliza o documento em volta de tudo isso.</div>]==] },
  { slug = [==[dados]==], group = [==[Aplicação]==], title = [==[Dados e endpoints]==], description = [==[Probes no servidor, endpoints HTTP e respostas em pedaços.]==], body = [==[<h2 id="probe"><a class="doc-anchor" href="#probe" aria-label="Link para esta seção">#</a>O probe de uma página</h2><p>Um <code>page.lua</code> ao lado de um <code>page.lunar</code> busca os dados daquela rota antes de ela ser renderizada. O que ele devolve chega ao componente como <code>data</code>.</p><figure class="doc-code"><figcaption>orbit/blog/[slug]/page.lua</figcaption><pre><code>local posts = require("lib.posts")

return {
  probe = function(event)
    local post = posts.get(event.params.slug)
    if not post then
      event.fail(404, "Post não encontrado")
    end
    return { title = post.title, post = post }
  end,
}</code></pre></figure><figure class="doc-code"><figcaption>orbit/blog/[slug]/page.lunar</figcaption><pre><code>&lt;script&gt;
  props { data = {} }
&lt;/script&gt;

&lt;h1&gt;{data.post.title}&lt;/h1&gt;</code></pre></figure><h2 id="o-evento"><a class="doc-anchor" href="#o-evento" aria-label="Link para esta seção">#</a>O que o probe recebe</h2><div class="doc-table"><table><thead><tr><th>Campo</th><th>O que é</th></tr></thead><tbody><tr><td><code>event.params</code></td><td>os segmentos dinâmicos da rota</td></tr><tr><td><code>event.query</code></td><td>a query string já separada</td></tr><tr><td><code>event.request</code></td><td>o pedido, com método, cabeçalhos e corpo</td></tr><tr><td><code>event.fail(status, mensagem)</code></td><td>renderiza o <code>eclipse</code> mais próximo</td></tr><tr><td><code>event.redirect(status, destino)</code></td><td>responde com um redirecionamento</td></tr></tbody></table></div><p><code>fail</code> e <code>redirect</code> interrompem a execução na hora, inclusive dentro de uma função auxiliar.</p><div class="doc-note warn">Um probe roda no servidor e também quando o navegador navega para a rota. Ele precisa produzir os mesmos dados para o mesmo estado: uma árvore diferente da que o servidor mandou faz o runtime reconstruir aquele trecho em vez de reivindicá-lo.</div><h2 id="endpoints"><a class="doc-anchor" href="#endpoints" aria-label="Link para esta seção">#</a>Endpoints</h2><p>Um <code>api.lua</code> responde a uma URL diretamente, sem página.</p><figure class="doc-code"><figcaption>orbit/api/notas/api.lua</figcaption><pre><code>return {
  get = function(event)
    return { ok = true, agora = os.time() }
  end,

  post = function(event)
    local corpo = event.request:json()
    if type(corpo) ~= "table" then
      event.fail(400, "esperava JSON")
    end
    salvar(corpo)
    return { status = 201, body = "" }
  end,
}</code></pre></figure><p>Uma tabela devolvida vira JSON; uma string vira HTML; uma tabela com <code>status</code>, <code>headers</code> ou <code>body</code> é usada como está.</p><h2 id="formularios"><a class="doc-anchor" href="#formularios" aria-label="Link para esta seção">#</a>Formulários</h2><p>Não há form actions integradas. Um formulário aponta para um endpoint, e o endpoint responde com um redirecionamento ou com JSON — o caminho continua funcionando sem JavaScript, porque é HTTP comum.</p><figure class="doc-code"><pre><code>&lt;form method="post" action="/api/notas"&gt;
  &lt;input name="texto" /&gt;
  &lt;button&gt;Salvar&lt;/button&gt;
&lt;/form&gt;</code></pre></figure><h2 id="streaming"><a class="doc-anchor" href="#streaming" aria-label="Link para esta seção">#</a>Respostas em pedaços</h2><p>Um endpoint pode responder aos poucos, em vez de montar tudo na memória.</p><figure class="doc-code"><figcaption>orbit/api/relatorio/api.lua</figcaption><pre><code>local response = require("lunar.http.response")

return {
  get = function(event)
    return response.stream(function(write)
      for _, linha in ipairs(relatorio()) do
        write(linha .. "\n")
      end
    end, 200, { ["Content-Type"] = "text/plain; charset=utf-8" })
  end,
}</code></pre></figure><p>A resposta sai com <code>Transfer-Encoding: chunked</code>, um pedaço por <code>write</code>, e a conexão segue viva depois. Quem escreve cede a vez sempre que o socket encheria, então um leitor lento custa uma corrotina e não o laço inteiro.</p><div class="doc-note">Um produtor que falha no meio já mandou corpo que não dá para desdizer: a conexão cai sem o pedaço final, que é o que avisa ao cliente que o corpo está incompleto. Um cliente HTTP/1.0 recebe os mesmos bytes juntos, com <code>Content-Length</code>. Em uma aplicação congelada para Workers, o stream é recolhido em uma resposta só.</div><p>Páginas não são transmitidas assim: o <code>&lt;lunar:head&gt;</code> é coletado enquanto o corpo renderiza, então a <code>&lt;head&gt;</code> só é conhecida no fim.</p>]==] },
  { slug = [==[renderizacao]==], group = [==[Aplicação]==], title = [==[Renderização e hidratação]==], description = [==[HTML no servidor. Continuidade no navegador.]==], body = [==[<h2 id="dois-destinos"><a class="doc-anchor" href="#dois-destinos" aria-label="Link para esta seção">#</a>Um componente, dois destinos</h2><p>O compilador gera um módulo Lua com duas funções a partir da mesma árvore: uma escreve HTML no servidor, a outra constrói a interface no navegador. A suíte de testes compara as duas saídas byte a byte — se divergirem, é um defeito.</p><h2 id="primeiro-carregamento"><a class="doc-anchor" href="#primeiro-carregamento" aria-label="Link para esta seção">#</a>O primeiro carregamento</h2><p>O servidor resolve a rota, roda os probes e renderiza a página inteira. Os dados seguem junto em um bloco <code>application/json</code>, que o navegador não executa. O conteúdo já está visível antes de qualquer Lua rodar no cliente.</p><h2 id="moonlight"><a class="doc-anchor" href="#moonlight" aria-label="Link para esta seção">#</a>Fengari e moonlight</h2><p>O Fengari executa Lua no navegador e o runtime moonlight — a aplicação como ela chega ao cliente, em um pacote só — conecta componentes, estado e DOM.</p><h2 id="hidratacao"><a class="doc-anchor" href="#hidratacao" aria-label="Link para esta seção">#</a>A tomada de controle</h2><p>Ao assumir, o runtime reivindica os nós que o servidor mandou em vez de substituí-los: percorre o mesmo template e casa cada nó com o que já está no documento, pendura os eventos e os efeitos nele e escreve apenas os atributos e textos que diferem. Os elementos mantêm a identidade, incluindo o foco, o que já foi digitado e as imagens já carregadas.</p><p>Quando a árvore não corresponde, o runtime não remenda: ele reporta a diferença e reconstrói o conteúdo daquele container.</p><h2 id="atualizacoes"><a class="doc-anchor" href="#atualizacoes" aria-label="Link para esta seção">#</a>Atualizações</h2><p>Textos e atributos são escritos diretamente; não há DOM virtual. Blocos condicionais e listas sem chave renderizam de novo quando o que leem muda. Uma lista com chave é reconciliada: as linhas que permanecem conservam seus nós e o estado dentro deles, e apenas o mínimo é movido.</p><h2 id="custo"><a class="doc-anchor" href="#custo" aria-label="Link para esta seção">#</a>O que o navegador baixa</h2><div class="doc-table"><table><thead><tr><th>Peça</th><th>Sem compressão</th><th>Com gzip</th></tr></thead><tbody><tr><td>Fengari</td><td>219 KB</td><td>68 KB</td></tr><tr><td>Pacote moonlight do exemplo</td><td>88 KB</td><td>18 KB</td></tr></tbody></table></div><p>Esse é o preço de rodar Lua no navegador em vez de compilar para JavaScript, e ele é pago uma vez por versão, depois que a página já está visível. O Lunar não comprime nada por conta própria — isso exigiria um DEFLATE em Lua —, mas serve o arquivo comprimido que estiver ao lado do original, e um proxy ou uma borda na frente fazem o mesmo trabalho.</p><div class="doc-note">Uma aplicação congelada para Cloudflare Workers ocupa cerca de 143 KB, e a plataforma comprime o que entrega.</div>]==] },
  { slug = [==[wasm]==], group = [==[Ir além]==], title = [==[Lua em WebAssembly]==], description = [==[Funções Lua compiladas para wasm, carregadas quando alguém precisa.]==], body = [==[<p>Um diretório <code>wasm/</code> ao lado de <code>orbit/</code> guarda arquivos Lua comuns cujas funções o Lunar compila para WebAssembly. O compilador é escrito em Lua, sem nada embaixo: não há toolchain, binário no repositório nem passo de build — uma parte é compilada em memória e guardada em cache como um componente.</p><figure class="doc-code"><figcaption>wasm/geometria.lua</figcaption><pre><code>function area(raio)
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
end</code></pre></figure><p>Um <code>function</code> é exportado pela sua parte; um <code>local function</code> fica dentro dela.</p><h2 id="subconjunto"><a class="doc-anchor" href="#subconjunto" aria-label="Link para esta seção">#</a>O que o subconjunto cobre</h2><ul><li>Aritmética com <code>+ - * / // % ^</code>, comparações, <code>and</code>, <code>or</code>, <code>not</code>.</li><li><code>if</code>, <code>while</code>, <code>for</code> numérico com passo literal, <code>break</code>, <code>local</code>, atribuição.</li><li>Strings com <code>..</code>, <code>#</code>, <code>==</code> e ordenação byte a byte.</li><li>Tabelas, construtores, <code>t[k]</code>, <code>t.k</code>, <code>#t</code>, <code>setmetatable</code>, <code>getmetatable</code>, <code>rawget</code>, <code>rawset</code>, <code>type</code>.</li><li>Funções como valor, closures sobre as variáveis em volta, vários retornos e um <code>...</code> final.</li><li><code>math.abs</code>, <code>math.ceil</code>, <code>math.floor</code>, <code>math.max</code>, <code>math.min</code>, <code>math.sqrt</code>, <code>math.trunc</code>.</li></ul><p><code>//</code> e <code>%</code> arredondam como no Lua, então <code>-7 % 3</code> é <code>2</code>. Corrotinas, métodos com <code>:</code>, <code>goto</code> e o resto da biblioteca padrão são recusados em tempo de compilação, com arquivo e linha.</p><h2 id="valores"><a class="doc-anchor" href="#valores" aria-label="Link para esta seção">#</a>Como os valores são guardados</h2><p>Todo valor é um <code>f64</code>, porque um número de Lua já é um. Os outros viajam nos NaN silenciosos que um double não usa: uma etiqueta e um endereço na memória. Aritmética não paga nada por isso, e <code>if v then</code> é falso exatamente para <code>nil</code> e <code>false</code>.</p><p>Strings são bytes na memória com o tamanho na frente; um literal é escrito na seção de dados do módulo, então alcançá-lo não aloca nada. Uma tabela tem parte de array para as chaves <code>1..n</code> e parte hash para o resto. Um número concatenado em uma string é escrito como o Lua escreve, com quatorze dígitos significativos — a diferença é que, sem subtipo inteiro, <code>3</code> sai <code>3</code> e não <code>3.0</code>.</p><h2 id="memoria"><a class="doc-anchor" href="#memoria" aria-label="Link para esta seção">#</a>A memória, e o que fazer sem coletor</h2><div class="doc-note warn">Não há coletor de lixo. O alocador empurra um ponteiro e não o traz de volta sozinho.</div><p>No lugar dele há uma arena explícita: <code>heap.mark()</code> lê o ponteiro e <code>heap.release(marca)</code> o devolve, liberando de uma vez tudo que foi alocado no meio. O contrato é o de qualquer arena: nada alocado depois da marca pode ser guardado depois do release.</p><figure class="doc-code"><pre><code>function moer(rodadas)
  local ultima = 0
  local rodada = 1
  while rodada &lt;= rodadas do
    local marca = heap.mark()
    local rascunho = { rodada }
    ultima = rascunho[1]
    heap.release(marca)
    rodada = rodada + 1
  end
  return ultima
end</code></pre></figure><h2 id="partes"><a class="doc-anchor" href="#partes" aria-label="Link para esta seção">#</a>Partes carregadas sob demanda</h2><p>Cada arquivo é uma parte, e uma parte só é buscada quando algo chama para dentro dela. Uma parte que chama uma função exportada por outra a importa pelo nome, o que torna a dependência real em vez de declarada.</p><figure class="doc-code"><pre><code>$ lunar wasm wasm/*.lua
runtime.wasm      10340 bytes  exports alloc closure_new concat ...
geometria.wasm      171 bytes  exports area hypotenuse
texto.wasm         1014 bytes  exports label summary  needs geometria runtime</code></pre></figure><p>O servidor compila as partes sob demanda e as serve em <code>/_lunar/wasm/</code>, com um <code>index.json</code> dizendo quem exporta o quê e quem precisa de quem. Uma aplicação congelada para Workers escreve os mesmos arquivos em <code>public/</code>: quem compila o WebAssembly é o navegador, não o Worker, então os dois alvos carregam bytes idênticos.</p><h2 id="no-componente"><a class="doc-anchor" href="#no-componente" aria-label="Link para esta seção">#</a>Usar de um componente</h2><figure class="doc-code"><pre><code>&lt;script&gt;
  area_de = nil

  local function medir()
    wasm("area", function(area) area_de = area(3) end)
  end
&lt;/script&gt;

&lt;button wasm:preload={"area"} on:click={medir}&gt;medir&lt;/button&gt;
&lt;output&gt;{area_de or "—"}&lt;/output&gt;</code></pre></figure><p><code>wasm(nome, pronto)</code> pede uma função e a entrega quando a parte dela chegou. Carregar é uma busca pela rede, então a resposta vem em um callback — e a página renderiza no servidor sem nada disso. O que volta já vem lido: número continua número, e <code>nil</code>, booleano e string chegam como são.</p><p><code>wasm:preload={"area"}</code> aquece a parte antes do clique: o elemento a pede quando o ponteiro chega, quando o foco cai nele ou quando um dedo encosta, uma vez só. A diretiva não renderiza nada — é comportamento, não marcação.</p><div class="doc-note">Uma função que recebe <code>...</code> não pode ser exportada por uma parte, porque quem a chama de fora não tem como passar os extras: deixe-a <code>local</code> e exporte outra que a chame. Corrotinas não existem no wasm; o lugar delas continua sendo o Lua que roda no Fengari, que pode chamar uma parte.</div>]==] },
  { slug = [==[seguranca]==], group = [==[Ir além]==], title = [==[Segurança]==], description = [==[O que vem ligado, e o que continua sendo seu.]==], body = [==[<h2 id="escapamento"><a class="doc-anchor" href="#escapamento" aria-label="Link para esta seção">#</a>Escapamento</h2><p>Texto em um template é escapado por padrão, em todo lugar: no corpo, em atributos e em strings interpoladas. <code>{@html}</code> é a única saída, e existe como sintaxe separada para que o ponto de uso diga o que está fazendo. Os dados da página viajam em um bloco <code>application/json</code>, que o navegador não executa.</p><h2 id="csp"><a class="doc-anchor" href="#csp" aria-label="Link para esta seção">#</a>Content Security Policy</h2><p>A política é gerada a partir da resposta, com <code>default-src 'none'</code> como ponto de partida para documentos. Um script embutido é autorizado pelo SHA-256 dos seus bytes — nunca por um nonce, nunca com <code>unsafe-eval</code>. Nada do que o Lunar entrega precisa de um dos dois: o Fengari vendorizado não tem <code>eval</code> nem <code>new Function</code>.</p><p>Respostas que não são documentos usam uma política mais fechada, com <code>frame-ancestors 'none'</code> e <code>sandbox</code>.</p><h2 id="cabecalhos"><a class="doc-anchor" href="#cabecalhos" aria-label="Link para esta seção">#</a>Cabeçalhos</h2><p>O servidor define <code>X-Content-Type-Options</code>, <code>Referrer-Policy</code>, <code>X-Frame-Options</code>, as políticas de origem cruzada e um <code>Permissions-Policy</code> que desliga as APIs de dispositivo.</p><h2 id="limite"><a class="doc-anchor" href="#limite" aria-label="Link para esta seção">#</a>Limite de requisições</h2><p>Há um limitador por endereço, em balde de fichas, com limites separados para páginas, arquivos e escritas. O rastreamento é limitado e entradas inativas são descartadas. Em um teste de carga, suba o servidor com <code>RATE_LIMIT=0</code>: o limitador existe para impedir exatamente o que um teste de carga faz.</p><h2 id="estaticos"><a class="doc-anchor" href="#estaticos" aria-label="Link para esta seção">#</a>Arquivos públicos</h2><p>Caminhos são normalizados antes de qualquer leitura, e nada fora da raiz de <code>static/</code> é servido. Cada arquivo sai com <code>ETag</code> e <code>Cache-Control</code>, e com <code>Vary: Accept-Encoding</code> — que agora é verdade, porque o servidor entrega o irmão <code>.br</code> ou <code>.gz</code> quando ele existe e o pedido aceita.</p><div class="doc-note warn">Nada disso substitui validar o que chega nos seus endpoints. O framework cuida do transporte e do documento; o significado dos dados é da aplicação.</div>]==] },
  { slug = [==[workers]==], group = [==[Ir além]==], title = [==[Cloudflare Workers]==], description = [==[A mesma aplicação, congelada para a borda.]==], body = [==[<figure class="doc-code"><pre><code>lunar workers meu-app</code></pre></figure><p>O comando escreve um diretório <code>.lunar/workers/</code> pronto para publicar.</p><div class="doc-table"><table><thead><tr><th>Caminho</th><th>O que é</th></tr></thead><tbody><tr><td><code>src/app.lua</code></td><td>o runtime, os componentes, os probes e a tabela de rotas em um arquivo só</td></tr><tr><td><code>src/worker.mjs</code></td><td>o ponto de entrada em JavaScript</td></tr><tr><td><code>public/</code></td><td>os arquivos públicos, servidos pela plataforma antes do Worker</td></tr><tr><td><code>wrangler.jsonc</code></td><td>a configuração do Worker</td></tr></tbody></table></div><h2 id="congelado"><a class="doc-anchor" href="#congelado" aria-label="Link para esta seção">#</a>O que muda em uma aplicação congelada</h2><ul><li>Nada lê um arquivo em tempo de requisição: o compilador e o servidor HTTP ficam de fora do pacote.</li><li>A ponte troca pedido e resposta como JSON, então as respostas são montadas como strings — um stream é recolhido em uma só.</li><li>O limitador de requisições vale por isolate.</li><li>As partes WebAssembly são escritas em <code>public/</code> e compiladas pelo navegador, não pelo Worker.</li></ul><h2 id="publicar"><a class="doc-anchor" href="#publicar" aria-label="Link para esta seção">#</a>Publicar</h2><figure class="doc-code"><pre><code>cd .lunar/workers
npm install
npx wrangler deploy</code></pre></figure><div class="doc-note">A suíte do framework carrega o pacote congelado com <code>io</code> e <code>package.path</code> retirados e compara as páginas dele, byte a byte, com as do servidor comum. É esse teste que garante que o alvo não saiu do lugar.</div>]==] },
  { slug = [==[cli]==], group = [==[Ir além]==], title = [==[Linha de comando]==], description = [==[Os comandos, e o que cada um faz.]==], body = [==[<div class="doc-table"><table><thead><tr><th>Comando</th><th>O que faz</th></tr></thead><tbody><tr><td><code>lunar dev [app]</code></td><td>sobe o servidor compilando sob demanda e recarregando</td></tr><tr><td><code>lunar build [app]</code></td><td>compila tudo uma vez e reporta o que falhou</td></tr><tr><td><code>lunar map [app]</code></td><td>imprime a tabela de rotas como ela foi descoberta</td></tr><tr><td><code>lunar compile &lt;arquivo&gt;</code></td><td>escreve na saída padrão o Lua gerado para um componente</td></tr><tr><td><code>lunar wasm &lt;arquivos&gt;</code></td><td>compila funções Lua em partes WebAssembly</td></tr><tr><td><code>lunar bench [app]</code></td><td>mede compilação, renderização, tomada de controle e download</td></tr><tr><td><code>lunar bench --http &lt;url&gt;</code></td><td>mede um servidor em pé por conexões keep-alive</td></tr><tr><td><code>lunar workers [app]</code></td><td>gera o diretório de deploy para Cloudflare Workers</td></tr><tr><td><code>lunar spec [nome...]</code></td><td>roda a suíte do framework</td></tr></tbody></table></div><h2 id="ambiente"><a class="doc-anchor" href="#ambiente" aria-label="Link para esta seção">#</a>Ambiente</h2><p><code>HOST</code> e <code>PORT</code> escolhem onde servir, <code>RATE_LIMIT=0</code> desliga o limitador para um teste de carga, e <code>WASM_OUT</code> diz onde <code>lunar wasm</code> deve escrever os arquivos.</p><h2 id="manifesto"><a class="doc-anchor" href="#manifesto" aria-label="Link para esta seção">#</a>lunar.json</h2><figure class="doc-code"><figcaption>lunar.json</figcaption><pre><code>{
  "name": "Meu app",
  "description": "O que ele é.",
  "lang": "pt-BR",
  "port": 3000
}</code></pre></figure><p>O manifesto na raiz da aplicação nomeia o projeto e ajusta o que o servidor precisa saber. <code>lunar.app(options)</code> aceita as mesmas opções diretamente, além de <code>client</code>, <code>dev</code>, <code>minify</code>, <code>stylesheets</code>, <code>security</code> e <code>rate_limit</code>.</p><h2 id="versoes"><a class="doc-anchor" href="#versoes" aria-label="Link para esta seção">#</a>Versões</h2><p>O número é lido como o do próprio Lua: <code>1.0</code> é a série e o último número é a release dentro dela. Uma mudança no que um componente ou uma aplicação significam sobe a série, como 5.3 e 5.4 são linguagens diferentes e não compilações diferentes.</p>]==] },
}

return pages
