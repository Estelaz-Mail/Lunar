<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/lunar-blue.svg">
    <img src="brand/lunar-violet.svg" alt="Lunar" width="190">
  </picture>
</p>

# Lunar

Lunar is a web framework for Lua, with reactive components, server rendering, and file-based routing.

## Getting started

```sh
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/Glazastyy/Lunar/main/install.sh | sh
```

The installer puts a checkout under `~/.lunar`, links a `lunar` launcher into `~/.local/bin`, and builds LuaSocket when the Lua on your machine has none. It writes nothing outside your home directory and never asks for root. `sh install.sh --help` lists the options: `--ref` for a branch or tag, `--prefix` and `--bin-dir` for where things go, `--lua` for an interpreter of your choosing, `--with-lua` to build Lua 5.4 into the prefix as well, `--no-modify-path` to leave your shell profile alone, and `--uninstall` to take it all out again. Lua and LuaSocket are downloaded from their own sites and checked against pinned SHA-256 sums.

From a clone, there is nothing to install: Lunar requires Lua 5.4, and LuaSocket only to serve.

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
<button on:click="{function()" count="count" + 1 end}>Count: {count}</button>

<style>
  h1 {
    color: var(--accent);
  }
</style>
```

Assignments in a component script are reactive by default. Lunar executes the script with `_ENV` bound to the component's scope, so an assignment such as `count = count + 1` updates the parts of the template that depend on `count`. Values declared with `local` remain ordinary Lua locals. Standard Lua globals such as `math`, `print`, and `require` are still available.

The component scope provides `props { name = value }` for default properties, `watch(fn)` for effects, and `derived(name, fn)` for computed values. `on_rise(fn)` runs when a component is added to the document, while `on_set(fn)` runs before its removal. Components can share values with descendants through `set_context` and `get_context`, and load other components using `import(path)` with paths relative to the current file.

Templates accept Lua expressions inside `{...}`. Text expressions are escaped; `{@html expr}` inserts HTML directly. Conditional blocks use `{#if}`, `{:else if}`, and `{:else}`, while `{#each list as item, i}` renders collections and supports an `{:else}` case for empty ones.

Attributes can contain expressions or interpolated strings, and tables can be spread with `{...table}`. Event handlers use directives such as `on:click` and `on:click|prevent`. The template syntax also includes `class:active`, `style:color`, `bind:value`, child components with capitalized names, `<slot />`, and `<lunar:head>` for document metadata. A literal opening brace can be written as `\{`.

Styles are scoped to their component. Lunar generates a class for the rendered elements and adjusts selectors during compilation. The `:global(...)` selector can be used for styles that should remain global.

## Compilation and rendering

A `.lunar` file compiles to a Lua module with separate functions for server rendering and browser DOM creation. The compiler parses the script, template, and styles, and reports errors against the original file and line numbers. Compiled components are cached by their source contents.

On the server, Lunar renders the requested route to HTML and includes its data in a JSON script element. In the browser, [Fengari](https://github.com/fengari-lua/fengari) executes the Lua application and Lunar's browser runtime, called _moonlight_, handles reactivity and navigation. Application components do not need to be translated into JavaScript.

Updates are applied directly to text nodes and attributes. Conditional and iteration blocks render again when their dependencies change. Lunar does not use a virtual DOM, and `{#each}` currently has no keyed form.

When the browser runtime takes over, it claims the nodes the server sent rather than replacing them. The client renderer walks the same template and matches each node it would have created against the one already in the document, attaches the event listeners and effects to it, and writes only the attributes and text that differ. Text that a parser merged into a single node is split where the template expects a boundary, and a block's content is claimed where the server left it. Nodes therefore keep their identity through the takeover, including input values a visitor has already typed, the focused element, and images and iframes that have already loaded.

A container that does not match what the page would have built is not patched into shape. The runtime reports the first difference it found, clears the container, and renders into it, which is the behaviour it had before it could claim nodes at all. The usual cause is a probe that returns different data on two consecutive renders.

Links between application routes load route data and update the page without a full reload. Navigations are numbered, so a response that arrives for a navigation the visitor has already left is discarded instead of replacing a newer page. Ordinary page loads continue to work without client-side navigation.

## Performance

`bin/lunar bench [app]` measures the framework against the application given to it: how long its components take to compile, how many pages a second one process renders along with the latency spread and the memory each page allocates, what the takeover costs, and how many bytes the browser downloads. The numbers depend on the machine, which the output names. On one core of an ordinary x86-64 Linux machine, the example application renders between 5,500 and 8,000 pages a second, at a median of 0.12 to 0.16 ms and a 99th percentile under 0.5 ms, allocating 42 to 58 KB per page. A page here is every probe, every component, and the whole document, rendered from nothing with no cache in front of it.

The browser downloads about 302 KB uncompressed for the example application: 215 KB of Fengari and 88 KB of application bundle. That is the cost of running Lua in the browser rather than compiling it to JavaScript, and it is paid once per version, after the server-rendered page is already visible. The same application frozen for an edge runtime is 143 KB.

`bin/lunar bench --http URL` drives a running server over keep-alive connections and reports requests a second and the latency spread. On the same machine as the server, with 32 keep-alive connections and the client in one process of its own, the example application answers about 4,200 requests a second at a median of 7.5 ms, 8.7 ms at the 95th percentile and 11.4 ms at the 99th. Both sides are competing for the same cores, so that is a floor rather than a ceiling. Run the server with `RATE_LIMIT=0` for a load test, since the rate limiter exists to stop exactly what a load test does.

The takeover is also measured, against the table DOM the tests use rather than a browser. Claiming is not faster than rebuilding there, and is not meant to look like it: in a table DOM a node costs a table. What claiming buys is the node itself, and in a browser a created node also costs layout and paint, which that measurement cannot capture.

The HTTP server is a single process with a single thread. Each connection runs in a coroutine, yields whenever its socket would block, and is resumed by a `socket.select` loop, so one thread serves many keep-alive connections. Read, keep-alive, and write deadlines are enforced by the loop itself rather than only when a client sends something, so a connection that goes quiet is dropped rather than holding its slot. The number of connections and the number of requests per connection are both bounded, and a connection past the limit is closed on accept.

A probe or an endpoint that blocks blocks the whole loop, because there is one thread to block. Work that waits should be kept off the request path, and an application that needs more than one core should run more than one process behind a proxy. `spec/concurrency_spec.lua` drives many concurrent connections, slow clients, partial writes, timeouts, and the connection limits through the real loop with a substituted socket library.

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
bin/lunar bench [app]
bin/lunar bench --http URL
bin/lunar workers [app]
bin/lunar spec
```

`dev` starts the development server, `build` compiles the application's components to check for errors, and `map` prints the discovered routes. `compile` writes the generated Lua for a component to standard output, `bench` measures compiling, rendering, the takeover, and the download, `workers` creates a Cloudflare Workers deployment, and `spec` runs the test suite.

## Formatting

Everything in the repository that is not Lua is formatted with Prettier: Markdown, YAML, JSON, CSS, HTML, and JavaScript. There is no package manifest at the root and nothing to install, since the version is named at the point of use:

```sh
npx prettier@3.9.10 --write .
npx prettier@3.9.10 --check .
```

The settings are in `.prettierrc`. Lua files are listed in `.prettierignore`, since Prettier has no Lua support; Lua in this repository uses two-space indentation, `snake_case` names, and no comments. The continuous integration workflow runs the check alongside the test suite.

## Repository structure

The implementation is under `lunar/`. Shared utilities for JSON, HTML escaping, URLs, MIME types, and files are in `lunar/core/`. The parser, CSS scoping, and code generation are in `lunar/compiler/`, while reactivity, server rendering helpers, and DOM handling are in `lunar/runtime/`.

Routing, rendering, the browser bundle, and deployment targets live under `lunar/site/`, with Cloudflare Workers support in `lunar/site/targets/`. The HTTP server, request handling, static files, and security are in `lunar/http/`. Example applications are in `examples/`, tests are in `spec/`, editor integrations are in `editors/`, and the project assets are in `brand/`.

## Testing and development status

The test suite contains 128 tests. It compares the HTML generated by the server renderer with the markup serialized from the Lua-based DOM renderer, checks the browser bundle against data produced by the server, and tests the packaged Workers application without filesystem access. It also parses the server's own markup the way a browser would and runs the takeover against it, for every route of the example application, asserting that each element afterwards is the one the server sent. The connection scheduling is tested by driving concurrent connections through the real server loop.

The compiler, component model, reactivity, routing, HTTP server, hydration, browser navigation, security defaults, Workers target, and VS Code extension are implemented. Keyed iteration, named slots, `{#await}`, built-in form actions, and streaming responses are not currently supported. Server-side form handling can be implemented through `api.lua` endpoints.

The codebase uses Lua 5.4, two-space indentation, `snake_case` names, and one returned table per module. Tests follow the `name_spec.lua` naming convention. Apart from LuaSocket for socket access, the framework's HTTP handling, compiler, runtime, and supporting modules are implemented in the repository.
