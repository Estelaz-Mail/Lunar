# Changelog

## 0.1.0

First release, alongside Lunar 0.1.0.

- Syntax highlighting for `.lunar`: Lua in the `<script>`, CSS in the
  `<style>`, and Lua in every expression in the template — `{count}`,
  `{#if …}`, `on:click={…}`, `attr={…}` and the rest.
- Diagnostics from the real compiler (`lunar compile`), as you type.
- **Lunar: Show the Lua this component compiles to**, beside the component.
- Commands for the dev server, the build check, the route table and the tests.
- Go to definition on `import("./Card.lunar")`.
- Snippets for Lunar's own shapes: `page`, `shell`, `probe`, `api`,
  `eclipse`, the blocks, and `event.fail`.
