<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/lunar-blue.svg">
    <img src="brand/lunar-violet.svg" alt="Lunar" width="190">
  </picture>
</p>

# Lunar

Lunar is a web framework for Lua, with reactive components, server rendering, and file-based routing.

## Getting started

Lunar requires Lua 5.4 and LuaSocket. You can run the included example with:

```sh
bin/lunar dev examples/tranquility
```

The development server listens on port 3000. Components are compiled when requested and cached until their source changes, so development does not require a separate build step.

## Components

Lunar components use the `.lunar` extension. Each file contains an HTML template, with an optional Lua `<script>` and a scoped `<style>` block.

```html
<script>
  props { title = "Lunar" }
  count = 0
</script>

<h1>{title}</h1>
<button on:click={function() count = count + 1 end}>
  Count: {count}
</button>

<style>
  h1 { color: var(--accent); }
</style>
```

Assignments in a component script are reactive by default. Lunar executes the script with `_ENV` bound to the component's scope, so an assignment such as `count = count + 1` updates the parts of the template that depend on `count`. Values declared with `local` remain ordinary Lua locals. Standard Lua globals such as `math`, `print`, and `require` are still available.

The component scope provides `props { name = value }` for default properties, `watch(fn)` for effects, and `derived(name, fn)` for computed values. `on_rise(fn)` runs when a component is added to the document, while `on_set(fn)` runs before its removal. Components can share values with descendants through `set_context` and `get_context`, and load other components using `import(path)` with paths relative to the current file.

Templates accept Lua expressions inside `{...}`. Text expressions are escaped; `{@html expr}` inserts HTML directly. Conditional blocks use `{#if}`, `{:else if}`, and `{:else}`, while `{#each list as item, i}` renders collections and supports an `{:else}` case for empty ones.

Attributes can contain expressions or interpolated strings, and tables can be spread with `{...table}`. Event handlers use directives such as `on:click` and `on:click|prevent`. The template syntax also includes `class:active`, `style:color`, `bind:value`, child components with capitalized names, `<slot />`, and `<lunar:head>` for document metadata. A literal opening brace can be written as `\{`.

Styles are scoped to their component. Lunar generates a class for the rendered elements and adjusts selectors during compilation. The `:global(...)` selector can be used for styles that should remain global.

## Compilation and rendering

A `.lunar` file compiles to a Lua module with separate functions for server rendering and browser DOM creation. The compiler parses the script, template, and styles, and reports errors against the original file and line numbers. Compiled components are cached by their source contents.

On the server, Lunar renders the requested route to HTML and includes its data in a JSON script element. In the browser, [Fengari](https://fengari.io) executes the Lua application and Lunar's browser runtime, called *moonlight*, handles reactivity and navigation. Application components do not need to be translated into JavaScript.

Updates are applied directly to text nodes and attributes. Conditional and iteration blocks render again when their dependencies change. Lunar does not use a virtual DOM, and `{#each}` currently has no keyed form.

The browser runtime currently rebuilds the rendered container when it takes over from the server instead of attaching to the existing DOM nodes. Links between application routes can then load route data and update the page without a full reload. Ordinary page loads continue to work without client-side navigation.

## Routing

Routes are defined by the directory structure under `orbit/`. A typical application looks like this:

```text
app/
  orbit/
    shell.lunar
    shell.lua
    page.lunar
    page.lua
    eclipse.lunar
    about/
      page.lunar
    blog/
      [slug]/
        page.lunar
    api/
      hello/
        api.lua
  lib/
  static/
  app.html
```

`page.lunar` renders a route, and `shell.lunar` wraps the pages beneath its directory through `<slot />`. Their corresponding `.lua` files can provide server-side data through a `probe` function. `api.lua` defines an HTTP endpoint, while `eclipse.lunar` handles errors and missing routes. Files in `static/` are served from the site root, and `app.html` can customize the document shell.

For example, `orbit/blog/[slug]/page.lua` can load a post using its URL parameter:

```lua
local posts = require("posts")

return {
  probe = function(event)
    local post = posts.get(event.params.slug)
    if not post then event.fail(404, "Post not found") end
    return { title = post.title, post = post }
  end,
}
```

Probes run before the page is rendered. Their returned values are exposed to the page as `data`, together with data returned by parent shells. `event.fail(status, message)` renders the nearest error boundary, and `event.redirect(status, location)` sends a redirect. Both stop the current operation immediately, including when called inside helper functions.

Dynamic route segments use `[name]`, catch-all segments use `[...name]`, and `(group)` directories organize routes without becoming part of the URL. Matching prioritizes literal segments, then parameters, then catch-all segments.

## Security

Lunar enables HTTP security headers and rate limiting by default. Its Content Security Policy is generated from the rendered response, with `default-src 'none'` as the starting policy for documents. Inline scripts are authorized by SHA-256 hashes rather than request-specific nonces. Application data is embedded as `application/json` and is not executed by the browser.

Non-document responses use a restrictive policy that includes `frame-ancestors 'none'` and `sandbox`. Lunar also sets `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`, cross-origin policies, and a `Permissions-Policy` that disables device APIs.

The HTTP server applies token-bucket rate limiting per client address, with separate limits for pages, assets, and write requests. Address tracking is bounded, and inactive entries can be discarded. Template expressions are escaped by default, with `{@html}` available when unescaped markup is required.

## Cloudflare Workers

Lunar can package an application for deployment to Cloudflare Workers:

```sh
bin/lunar workers examples/tranquility
cd examples/tranquility/.lunar/workers
npm install
npx wrangler dev
npx wrangler deploy
```

The generated deployment contains the application and its compiled routes in `src/app.lua`, the JavaScript entry point in `src/worker.mjs`, compatibility modules in `src/fs-stub.cjs` and `src/absent.cjs`, static assets in `public/`, and the Worker configuration in `wrangler.jsonc`.

The packaged Lua application does not read files or open sockets at runtime. Cloudflare handles incoming requests and static assets, while Fengari executes the compiled application. The bridge exchanges requests and responses as JSON, so responses are buffered as strings. Rate limiting is scoped to each Worker isolate.

The Workers bundle is tested separately from the normal server, including execution with filesystem access removed, to check that both targets produce the same page output.

## Editor support

The VS Code extension in `editors/vscode/` provides syntax highlighting for Lua, HTML, and CSS in `.lunar` files. It uses Lunar's compiler for diagnostics, supports definition lookup for imported components, and can display the Lua generated from a component.

To validate and package the extension:

```sh
cd editors/vscode
npm run check
npx @vscode/vsce package
code --install-extension lunar-lang-0.1.0.vsix
```

## CLI

The command-line interface is available through `bin/lunar`:

```sh
bin/lunar dev [app]
bin/lunar build [app]
bin/lunar map [app]
bin/lunar compile file
bin/lunar workers [app]
bin/lunar spec
```

`dev` starts the development server, `build` compiles the application's components to check for errors, and `map` prints the discovered routes. `compile` writes the generated Lua for a component to standard output, `workers` creates a Cloudflare Workers deployment, and `spec` runs the test suite.

## Repository structure

The implementation is under `lunar/`. Shared utilities for JSON, HTML escaping, URLs, MIME types, and files are in `lunar/core/`. The parser, CSS scoping, and code generation are in `lunar/compiler/`, while reactivity, server rendering helpers, and DOM handling are in `lunar/runtime/`.

Routing, rendering, the browser bundle, and deployment targets live under `lunar/site/`, with Cloudflare Workers support in `lunar/site/targets/`. The HTTP server, request handling, static files, and security are in `lunar/http/`. Example applications are in `examples/`, tests are in `spec/`, editor integrations are in `editors/`, and the project assets are in `brand/`.

## Testing and development status

The test suite contains 108 tests. It compares the HTML generated by the server renderer with the markup serialized from the Lua-based DOM renderer, checks the browser bundle against data produced by the server, and tests the packaged Workers application without filesystem access.

The compiler, component model, reactivity, routing, HTTP server, browser navigation, security defaults, Workers target, and VS Code extension are implemented. Claim-based hydration, keyed iteration, named slots, `{#await}`, built-in form actions, and streaming responses are not currently supported. Server-side form handling can be implemented through `api.lua` endpoints.

The codebase uses Lua 5.4, two-space indentation, `snake_case` names, and one returned table per module. Tests follow the `name_spec.lua` naming convention. Apart from LuaSocket for socket access, the framework's HTTP handling, compiler, runtime, and supporting modules are implemented in the repository.
