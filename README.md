<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/lunar-blue.svg">
    <img src="brand/lunar-violet.svg" alt="Lunar" width="190">
  </picture>
</p>

# Lunar

A web framework in Lua. One language on both sides of the request: the server
renders your components to HTML, and the same components then run in the
browser, from the same source, with nothing compiled to JavaScript in between.

```html
<!-- orbit/page.lunar -->
<script>
  props { title = "Lunar" }
  count = 0
  derived("doubled", function() return count * 2 end)
</script>

<h1>{title}</h1>
<button on:click={function() count = count + 1 end}>
  clicked {count} times — that is {doubled} halves
</button>

{#if count > 9}
  <p>that escalated</p>
{/if}

<style>
  h1 { color: var(--accent); }
</style>
```

## What Lunar is

- **One language, both sides.** A component is Lua. It renders to a string on
  the server and runs in the browser under [Fengari](https://fengari.io), a
  Lua virtual machine in JavaScript. You never write JavaScript, and Lunar
  never generates any.
- **A compiler, not a runtime library.** A `.lunar` file becomes a plain Lua
  module with two functions in it — one that writes HTML, one that builds
  nodes. `lunar compile` prints it. There is no virtual DOM and no diff.
- **State is a global in a component script.** Not a wrapper, not a store, not
  a macro: `count = count + 1` is reactive because of what `_ENV` means in
  Lua. See below — it is the idea the whole framework turns on.
- **No build step.** Components compile in memory, on demand, cached by their
  own bytes. There is no `dist/`, nothing generated in your repository, and
  nothing to go stale.
- **No dependencies.** Lua 5.4 and LuaSocket, which supplies the socket
  syscalls and nothing else. The HTTP/1.1 server, the router, the compiler,
  the reactivity, JSON, SHA-256 and the DOM layer are all here.
- **Secure from the first request.** A Content Security Policy, the rest of
  the header set and a per-address rate limiter are on by default, and the
  policy is derived from what your app actually renders.

### Prior art

Svelte showed that a component can be compiled away instead of interpreted,
and SvelteKit that the filesystem is a good router. Lunar is built on those
two ideas and is otherwise its own: a different language, a different
reactive model (Lua's `_ENV`, not a compiler rewriting your assignments), its
own vocabulary, its own browser runtime, and its own answer for deployment.
Where a borrowed name would have been the clearest one, Lunar keeps it; where
Lunar does something of its own, it says so in its own words.

## The component

A `.lunar` file is one component: a `<script>` of Lua, a template, and an
optional `<style>`. The three are split textually — the first top-level
`<script>`, the first top-level `<style>` — and the cut-out parts are replaced
by their own newlines, so **every line number the compiler reports is a line
number in the file you are looking at**.

### State is a global in a component script

The `<script>` is compiled as `function(_ENV) ... end`, with `_ENV` bound to
the component's scope. An undeclared assignment is therefore not a global — it
is a signal:

```lua
count = 0            -- component state, reactive
local total = 0      -- a plain local, not reactive, not in the template
```

A plain `count = count + 1` anywhere — in a handler, in a function, in a
callback three calls deep — is a tracked write, and everything in the template
that read `count` updates. There is no `$state`, no setter, no store, and no
compiler rewriting your assignments. Reads fall through to the real globals, so
`print`, `math` and `require` still work and are not state.

The scope provides these, and nothing else:

| In the script      | What it does                                               |
| ------------------ | ---------------------------------------------------------- |
| `props { k = v }`  | declares props with defaults; given props are already set   |
| `watch(fn)`        | runs `fn` now and whenever anything it read changes         |
| `derived(k, fn)`   | state computed from state: `derived("total", fn)`           |
| `on_rise(fn)`      | moonrise: the component is in the document (browser only)   |
| `on_set(fn)`       | moonset: the component is about to be removed               |
| `set_context(k,v)` | a value visible to descendants                              |
| `get_context(k)`   | the nearest ancestor's value                                |
| `import(path)`     | another component, resolved relative to this file           |

### Template syntax

| Syntax                                      | Meaning                                |
| ------------------------------------------- | -------------------------------------- |
| `{expr}`                                    | text, escaped                          |
| `{@html expr}`                              | markup, not escaped — the call site says so |
| `{#if a}…{:else if b}…{:else}…{/if}`        | branching                              |
| `{#each list as item, i}…{:else}…{/each}`   | iteration, with an empty case          |
| `attr={expr}` `attr="a {expr} b"`           | dynamic attributes                     |
| `{name}`                                    | shorthand for `name={name}`            |
| `{...table}`                                | spread attributes                      |
| `on:click={fn}` `on:click\|prevent={fn}`    | events, with modifiers                 |
| `class:active={expr}`                       | a class toggled by an expression       |
| `style:color={expr}`                        | one style property                     |
| `bind:value={target}`                       | two-way binding on a form control      |
| `<Card title={t}>…</Card>`                  | a child component (capitalised tag)    |
| `<slot />`                                  | where a component's children go        |
| `<lunar:head>…</lunar:head>`                | content hoisted into the document head |
| `\{`                                        | a literal brace                        |

Every expression is a **Lua expression**, checked at compile time: a typo is a
compile error with a file and a line, never a half-rendered page.

### Styles are scoped

A `<style>` applies to its own component. Every element it renders carries a
generated class (`l-1a2b3c4d`) and every selector is rewritten to require it:
`h1 { }` becomes `h1.l-1a2b3c4d { }`. `:global(body) { }` opts out. No shadow
DOM, no runtime cost.

## The orbit

An app's URLs are a directory tree under `orbit/`. A directory **is** a URL,
and the files in it are what that URL is made of:

```
app/
  orbit/
    shell.lunar            wraps everything below it
    shell.lua              its probe
    page.lunar             /
    page.lua               the page's probe
    eclipse.lunar          what a failure or a miss renders
    about/page.lunar       /about
    blog/[slug]/page.lunar /blog/:slug
    api/hello/api.lua      an endpoint: GET, POST, …
  lib/                     your own modules, and components to import
  static/                  served at the site root
  app.html                 optional document shell
```

Six names, no prefixes to remember:

| File            | What it is                                                     |
| --------------- | -------------------------------------------------------------- |
| `page.lunar`    | the page                                                        |
| `page.lua`      | its **probe**                                                   |
| `shell.lunar`   | wraps this directory and everything under it, around a `<slot/>`|
| `shell.lua`     | the shell's own probe                                           |
| `api.lua`       | an endpoint; a directory with one and no page is only ever data |
| `eclipse.lunar` | what renders when the light goes out: a failure, or a miss      |

A **probe** is what a page sends ahead of itself. It runs on the server, before
anything is drawn, and what it brings back is the page's `data`:

```lua
-- orbit/blog/[slug]/page.lua
local posts = require("posts")

return {
  probe = function(event)
    local post = posts.get(event.params.slug)
    if not post then event.fail(404, "No post called that.") end
    return { title = post.title, post = post }
  end,
}
```

`event.fail(status, message)` stops the render and shows the nearest eclipse;
`event.redirect(status, location)` sends a redirect. Both are raised, so they
work from inside a helper and no caller can forget to check a return value.

A page sees its shells' data merged into its own. `[slug]` is one segment and
`[...rest]` is the rest of the path; a literal beats a parameter, a parameter
beats a catch-all, and `(group)` directories shape the tree without shaping
the URL.

## Rendering: the surface and the moonlight

1. The server runs the probes, renders the chain of shells around the page,
   and sends one HTML document — complete, readable without scripts, indexable.
2. That document carries its data as JSON and loads Fengari plus the
   **moonlight**: the same app, assembled from source into one file for the
   browser.
3. The moonlight takes the container over. Every dynamic part of a template is
   an effect; a text node or an attribute patches in place, a block re-renders
   as a whole. Following a link fetches the next route's data and swaps the
   page without a reload; a full reload is always a working fallback.

**Stated plainly:** the takeover *rebuilds* the container rather than claiming
the server's nodes. First paint is the server's HTML; the moonlight then
renders over it. Claim-based hydration is a contained change inside
`lunar/runtime/dom.lua` and nothing above it has to move.

`{#each}` has no keyed form, on purpose: a keyed block implies a diff, and the
block re-render is the honest description of what this runtime does.

## Security

On by default, and derived from the app rather than configured beside it:

- **CSP** with `default-src 'none'` for documents and
  `default-src 'none'; frame-ancestors 'none'; sandbox` for everything else.
  Inline scripts are allowed by the **SHA-256 of their bytes**, never a nonce,
  so a cached response is still a safe response. Lunar's own document has no
  executable inline script at all: the page's data is an
  `application/json` block, which a browser does not run.
- `nosniff`, `Referrer-Policy`, `X-Frame-Options`, the cross-origin policies,
  and a `Permissions-Policy` that denies every device API.
- **Rate limiting**: a token bucket per client address in three classes —
  `page`, `asset`, `write` — because one limit cannot fit both a page view and
  the twenty files it pulls. It remembers a bounded number of addresses and
  forgets a visitor the moment their bucket is full again.
- Escaping is the default everywhere; `{@html}` is the single documented way
  past it.

## Deploying to Cloudflare Workers

The shape is the one a Rust Worker uses: the app becomes something the edge
runtime can execute, and a small JavaScript entry hands it the request. For
Rust that artifact is WebAssembly; for Lunar it is one Lua file on Fengari — so
there is no WebAssembly toolchain, and no second implementation of anything.

```sh
lunar workers examples/tranquility
cd examples/tranquility/.lunar/workers
npm install
npx wrangler dev       # http://localhost:8787
npx wrangler deploy
```

| Path               | What it is                                                   |
| ------------------ | ------------------------------------------------------------ |
| `src/app.lua`      | the whole app, frozen: runtime, components, probes, routes    |
| `src/worker.mjs`   | the entry: `fetch` in, `fetch` out                            |
| `src/fs-stub.cjs`  | what Fengari's `fs` import resolves to — a Worker has no disk |
| `src/absent.cjs`   | the same for `readline-sync` and `child_process`              |
| `public/`          | the static files, served by the platform, not by the app      |
| `wrangler.jsonc`   | the Worker, its assets, its module rules                      |

**Frozen** means exactly that: `src/app.lua` opens no file and no socket. The
route table, every compiled component and every probe are in it, and
`spec/workers_spec.lua` loads it in a Lua state with `io` and `package.path`
taken away, then serves the same pages the ordinary server serves, byte for
byte.

What changes at the edge, and nothing else does: there are no sockets, so the
platform is the server; static files are the platform's, through the assets
binding; the rate limiter counts per isolate, so it is a floor and not a
ceiling; and a response is a string, because the bridge is JSON.

## Editor support

`editors/vscode/` is a VS Code extension: highlighting that knows a `.lunar`
file is three languages at once, diagnostics from the real compiler rather than
a second parser, **Show the Lua this component compiles to**,
go-to-definition on `import("./Card.lunar")`, and snippets. Plain JavaScript,
no build step, for the same reason the framework has none.

```sh
cd editors/vscode && npm run check     # grammar and manifest, no editor needed
npx @vscode/vsce package && code --install-extension lunar-lang-0.1.0.vsix
```

## Layout of this repository

| Directory            | What lives there                                            |
| -------------------- | ----------------------------------------------------------- |
| `lunar/core/`        | strings, JSON, HTML escaping, URLs, MIME, files              |
| `lunar/compiler/`    | the `.lunar` splitter, template parser, CSS scoper, codegen  |
| `lunar/runtime/`     | signals, the component scope, SSR helpers, the DOM layer     |
| `lunar/site/`        | the orbit, the render pipeline, the moonlight, the targets   |
| `lunar/http/`        | HTTP/1.1, request, response, router, static files, security  |
| `lunar/site/targets/`| deploy targets; Cloudflare Workers is the one that exists    |
| `examples/`          | an app that uses every feature, which is also a test fixture |
| `spec/`              | the tests, one file per module, `name_spec.lua`              |
| `editors/vscode/`    | the VS Code extension                                        |
| `brand/`             | the logo, and the one script that derives the rest of it     |

## Commands

```sh
bin/lunar dev [app]        # serve an app on :3000, compiling on demand
bin/lunar build [app]      # compile everything once and report what failed
bin/lunar map [app]        # print the route table as it was discovered
bin/lunar compile file     # print the Lua a component compiles to
bin/lunar workers [app]    # generate a Cloudflare Workers deploy directory
bin/lunar spec             # run the test suite
```

## How it is tested

The compiler's output is checked against both renderers at once: a component is
rendered to a string **and** built into a DOM made of Lua tables, and the two
must serialise to the same markup. That is what keeps the two code generators
from drifting apart without a browser in the loop. The moonlight bundle is then
loaded in a bare Lua state and mounted against the payload the server really
serialised, and the frozen Workers bundle is loaded with `io` taken away and
compared with the ordinary server page by page.

## Where it stands

`bin/lunar spec` is 108 tests, all passing.

Done: the compiler (splitter, template parser, CSS scoper, both code
generators); reactivity (signals, effects, the `_ENV` scope, `derived`); every
row of the syntax table; components, props, slots, context and lifecycle; the
orbit, shells, probes, endpoints and eclipses; the surface, the moonlight,
takeover and client-side navigation; the HTTP/1.1 server, router, static files,
security headers and rate limiting; the Cloudflare Workers target, verified
against `workerd`; the VS Code extension.

Not done, and why:

| Missing                 | Why                                                  |
| ----------------------- | ---------------------------------------------------- |
| Claim-based hydration   | The moonlight rebuilds the container instead         |
| Keyed `{#each}`         | It would imply a diff this runtime does not do       |
| Named slots, `{#await}` | Not needed yet; both are contained additions         |
| Form actions            | An `api.lua` beside the page does the same job today |
| Streaming responses     | The Workers bridge is a string                       |

## Conventions

- Lua 5.4, two-space indent, `snake_case`, modules return one table.
- A comment says *why*, not what; the code already says what.
- One module per file, one spec per module.
- No dependency. That is the point of this framework, not an accident of it.
