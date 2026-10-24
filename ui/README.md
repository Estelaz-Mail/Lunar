# Lunar UI

Lunar UI é a biblioteca visual oficial do framework. Ela fornece componentes `.lunar`, ícones SVG e tokens CSS para aplicações que precisam de uma base consistente sem Chakra UI, Emotion ou React.

## Importar componentes

Componentes da biblioteca podem ser importados diretamente pelo namespace do framework:

```html
<script>
  local Button = import("lunar/ui/Button")
  local Card = import("lunar/ui/Card")
  salvar = function() end
</script>

<Card title="Conta">
  <Button label="Salvar" onclick={salvar} />
</Card>
```

## Estilos

Os tokens e o reset são arquivos públicos do framework e podem ser adicionados ao manifesto:

```json
{
  "stylesheets": [
    "/_lunar/ui/tokens.css",
    "/_lunar/ui/reset.css"
  ]
}
```

Aplicações congeladas também podem copiar esses arquivos para `static/css` e servi-los pela própria origem.

## Estado atual

A primeira versão cobre botões, cartões, stacks, badges, alertas, campos, spinners e ícones. Componentes de navegação, modal, drawer, tabelas, abas, tooltips, tema persistido e adaptadores de serviços externos continuam no roadmap registrado no `platform`.
