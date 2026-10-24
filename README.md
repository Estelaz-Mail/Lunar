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
curl --proto '=https' --tlsv1.2 -sSf https://lunar.estelaz.com/install.sh | sh
```

The same script is in this repository, and `https://raw.githubusercontent.com/Estelaz-Mail/Lunar/main/install.sh` serves it too.

The installer puts a checkout under `~/.lunar`, links a `lunar` launcher into `~/.local/bin`, and builds LuaSocket when the Lua on your machine has none. It installs the newest release, which it asks GitHub for; `--ref` takes a branch, a tag or a commit instead, and a machine that cannot reach the release list falls back to `main` and says so. It writes nothing outside your home directory and never asks for root. `sh install.sh --help` lists the options: `--ref` for a branch or tag, `--prefix` and `--bin-dir` for where things go, `--lua` for an interpreter of your choosing, `--with-lua` to build Lua 5.4 into the prefix as well, `--no-modify-path` to leave your shell profile alone, and `--uninstall` to take it all out again. Lua and LuaSocket are downloaded from their own sites and checked against pinned SHA-256 sums.

From a clone, Lunar requires Lua 5.4, and LuaSocket only to serve. Run this once from the repository root to install its launcher locally:

```sh
sh install.sh --from .
lunar dev examples/tranquility
```

The development server listens on port 3000. It compiles components when they are requested and caches them by their own bytes, so an edit is live on the next request; it also notices files that appear or disappear, so a new route works without a restart. Pages opened from it reload themselves when anything in the application changes: the browser half polls `/_lunar/dev` for a counter the server moves when it sees a difference, and that endpoint and the script that polls it exist only in development.

Development errors show the source file, line and surrounding code in the terminal. Repeated requests report the same error once until a watched file changes. Error pages use an independent reload module so fixing a broken component restores the page without compiling the failed bundle first.

Interactive terminals display a lunar theme, and the installer animates download and compilation progress. Set `NO_COLOR=1` for plain output, or `LUNAR_ANIMATIONS=0` to disable installer animations while keeping colors. Redirected output and CI logs stay plain; `--quiet` silences installer progress.

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

Templates accept Lua expressions inside `{...}`. Text expressions are escaped; `{@html expr}` inserts HTML directly. Conditional blocks use `{#if}`, `{:else if}`, and `{:else}`, while `{#each list as item, i}` renders collections and supports an `{:else}` case for empty ones. An iteration can name a key with `{#each list as item (item.id)}`, which identifies each row across updates.

Attributes can contain expressions or interpolated strings, and tables can be spread with `{...table}`. Event handlers use directives such as `on:click` and `on:click|prevent`. The template syntax also includes `class:active`, `style:color`, `bind:value`, child components with capitalized names, `<slot />` and `<slot name="footer" />` for content a parent passes in with `slot="footer"`, and `<lunar:head>` for document metadata. A literal opening brace can be written as `\{`.

Styles are scoped to their component. Lunar generates a class for the rendered elements and adjusts selectors during compilation. The `:global(...)` selector can be used for styles that should remain global.

## Lunar UI

The framework includes a small visual library under the `lunar/ui` namespace. Applications can import `Button`, `Card`, `Stack`, `Badge`, `Alert`, `Field`, `Spinner` and `Icon` without installing a JavaScript UI runtime:

```html
<script>
  local Button = import("lunar/ui/Button")
</script>

<Button label="Continue" />
```

The same directory contains the Lunar tokens and reset stylesheet. They are served at `/_lunar/ui/` and copied into generated Workers deployments.

## Compilation and rendering

A `.lunar` file compiles to a Lua module with separate functions for server rendering and browser DOM creation. The compiler parses the script, template, and styles, and reports errors against the original file and line numbers. Compiled components are cached by their source contents.

On the server, Lunar renders the requested route to HTML and includes its data in a JSON script element. In the browser, the official Lua 5.4 virtual machine compiled to WebAssembly executes the Lua application and Lunar's browser runtime, called _moonlight_, handles reactivity and navigation. Application components do not need to be translated into JavaScript.

Updates are applied directly to text nodes and attributes. Conditional blocks and unkeyed iteration blocks render again when their dependencies change. Lunar does not use a virtual DOM.

A keyed `{#each}` reconciles instead of rendering again. Lunar matches the new list against the rows it already built, keeps a row whose key and item are unchanged, destroys the rows whose keys are gone, builds the rows whose keys are new, and moves the smallest number of rows that puts the list back in order. A kept row therefore holds on to its DOM nodes, its component state, and whatever the browser attached to them. A row is rebuilt when its item is no longer the same value, so a keyed block updates through the state its rows read rather than through mutation of the items themselves. Two rows with the same key is an error, and so is a key that is `nil`.

When the browser runtime takes over, it claims the nodes the server sent rather than replacing them. The client renderer walks the same template and matches each node it would have created against the one already in the document, attaches the event listeners and effects to it, and writes only the attributes and text that differ. Text that a parser merged into a single node is split where the template expects a boundary, and a block's content is claimed where the server left it. Nodes therefore keep their identity through the takeover, including input values a visitor has already typed, the focused element, and images and iframes that have already loaded.

A container that does not match what the page would have built is not patched into shape. The runtime reports the first difference it found, clears the container, and renders into it, which is the behaviour it had before it could claim nodes at all. The usual cause is a probe that returns different data on two consecutive renders.

Links between application routes load route data and update the page without a full reload. Navigations are numbered, so a response that arrives for a navigation the visitor has already left is discarded instead of replacing a newer page. Ordinary page loads continue to work without client-side navigation.

The document supplies SHA-256 hashes for all executable browser runtime resources. Bootstrap and bridge use Subresource Integrity; the VM, moonlight bundle, Wasm index and application Wasm parts are checked before use. The trust boundary and limits are documented in [runtime/README.md](runtime/README.md).

## The manifest

An application can declare itself in a `lunar.json` at its root. Every field is optional, and anything passed to `lunar.app` or `lunar.serve` in code takes precedence over the file; `HOST` and `PORT` in the environment take precedence over the file's `host` and `port`.

```json
{
  "name": "Tranquility",
  "description": "The example app, which is also a fixture for the specs.",
  "lang": "en",
  "port": 3000
}
```

| Field         | What it is                                                                 |
| ------------- | -------------------------------------------------------------------------- |
| `name`        | The application's name, and the document title when a page sets none.      |
| `version`     | The version in asset URLs. Default: the time the process started.          |
| `lang`        | The `lang` attribute of the document.                                      |
| `host`        | The address to bind. Default: `0.0.0.0`, or `127.0.0.1` under `lunar dev`. |
| `port`        | The port to bind. Default: 3000.                                           |
| `client`      | `false` leaves the browser half out of the document entirely.              |
| `dev`         | Development mode: live reload, no caching, errors in the response.         |
| `minify`      | Whether the bundles are minified. Default: on outside development.         |
| `compress`    | Whether textual responses are gzipped. Default: on outside development.    |
| `prerender`   | `true`, or a list of paths, to render once and answer from memory.         |
| `stylesheets` | Stylesheet URLs to link in every document.                                 |
| `security`    | Overrides for the security headers and the Content Security Policy.        |
| `rate_limit`  | Overrides for the token buckets, in the shape `lunar.app` takes.           |

A third-party script or an API on another origin is declared in `security.extra`, which widens one directive and leaves the rest of the policy alone:

```json
{
  "security": {
    "extra": {
      "script-src": ["https://cdn.example.com"],
      "connect-src": ["https://api.example.com"]
    }
  }
}
```

An inline script is allowed by the SHA-256 of its bytes through `security.script_hashes`, never by a nonce and never by `unsafe-eval`. Lunar's bridge interprets Lua through the Lua 5.4 WebAssembly VM without generating JavaScript. The document policy allows `'wasm-unsafe-eval'` for WebAssembly compilation while keeping JavaScript string evaluation blocked. The document's own data is an `application/json` block a browser does not run.

`description`, `author`, `license`, `repository`, `homepage`, `keywords` and `private` are allowed and ignored, so a manifest can carry what a package registry would want. Any other key is an error naming the key, as is a field of the wrong type: a manifest that does not do what it says is worse than no manifest.

There are no `scripts`. Running arbitrary commands would mean shelling out, which this framework does in exactly two places, both at build time, and a task runner is not worth being the third.

## Performance

`lunar bench [app]` measures the framework against the application given to it: how long its components take to compile, how many pages a second one process renders along with the latency spread and the memory each page allocates, what the takeover costs, and how many bytes the browser downloads. The numbers depend on the machine, which the output names. On one core of an ordinary x86-64 Linux machine, the example application renders between 5,500 and 8,000 pages a second, at a median of 0.12 to 0.16 ms and a 99th percentile under 0.5 ms, allocating 42 to 58 KB per page. A page here is every probe, every component, and the whole document, rendered from nothing with no cache in front of it.

The browser fetches a small module bootstrap, the TypeScript host bridge, the Lua 5.4 Wasm VM and the moonlight application bundle as separate versioned resources. Applications with `client = false` emit none of them. The VM includes the Lua parser and standard libraries; those are currently one Wasm module, not separately loaded libraries. `lunar bench examples/tranquility` reports the current uncompressed sizes.

Outside development the framework's own modules are minified on their way into both bundles: comments, indentation and blank lines go, strings and line breaks stay. `minify` in the manifest, `MINIFY=0` in the environment, or `minify = false` passed to `lunar.app` turns it off. It is worth about 5%, because this source carries no comments to drop — 88 KB becomes 83 KB, and the frozen application 145 KB becomes 136 KB. The generated component modules are left alone on purpose: minifying them saves another 1.4 KB and costs the line numbers that make a runtime error point back at the `.lunar` file.

Compression changes the comparison: the Lua 5.4 VM is about 196 KiB uncompressed and 90 KiB with gzip, while the bridge adds about 3 KiB with gzip. This replacement is larger with gzip than the previous runtime; modular resources do not by themselves reduce the bytes needed to start the VM.

Lunar compresses what it serves. Outside development, a textual response of at least 1 KiB is deflated into a gzip stream when the request accepts one: a page, a JSON payload, a bundle, an error, a static file with nothing precompressed beside it. `lunar/core/gzip.lua` is the compressor, LZ77 over a 32 KiB window into fixed Huffman blocks, and `lunar/http/compress.lua` decides. The deflate stream and its CRC-32 are the format proper, so any client, proxy or `gzip -d` reads them.

It costs about 2.4 MB a second, which is a real cost and the reason the result is cached by the bytes it came from: a body that repeats is compressed once, and the website's stylesheet of 27,158 bytes becomes 8,064 in 11 ms, a rendered page of 12,534 bytes becomes 4,799 in 5 ms, and every later request for either pays nothing. A body unique to each request pays that cost each time. Development never compresses, so the bytes on the wire stay readable; `compress` in the manifest or `compress = false` passed to `lunar.app` turns it off everywhere, which is what to do behind a proxy that already compresses. An app frozen for Workers leaves it to the platform.

Brotli is not generated. It needs a static dictionary and context modelling that this source is not going to carry, and guessing at a worse brotli than every browser already has is not a trade worth making. A static file is still served from the precompressed file beside it when the request accepts that encoding: `app.js.br` for `br` and `app.js.gz` for `gzip`, preferred in that order and over compressing anything on the fly, with the original's content type, the compressed length, its own entity tag, and `Content-Encoding` set. Nothing generates those files, so they are the operator's to produce and to keep in step with the source. `Vary: Accept-Encoding` is on any response that could have been compressed, added to a `Vary` that was already there rather than replacing it, and an entity tag gains a `-gzip` suffix when the body is compressed, so a cache cannot hand a compressed body to a client that did not ask for one.

`lunar analyze [app]` weighs what it ships. Every resource the browser fetches is listed raw and gzipped, and the moonlight bundle is broken into the parts it is made of — each framework module, each component, the route registry, the start-up tail — sorted by weight, with each part's share of the bundle and what it costs compressed on its own. Those compressed figures add up to more than the bundle does, because the bundle is one stream and a part is not, and the report says so rather than presenting a sum that does not hold. The inventory is collected by building the bundle once with the parts kept; the server never holds that copy, and an ordinary build keeps none.

`lunar prerender [app]` renders every route that has no parameter in it and writes each one where a static host expects it: `/` to `index.html`, `/about` to `about/index.html`. It renders through the ordinary request path, so a prerendered page is the page the server would have answered, byte for byte, probes and all — `spec/prerender_spec.lua` asserts exactly that rather than trusting it. A route with a `[parameter]` is not rendered, because nothing says which values exist. `LUNAR_OUT` chooses the directory; it defaults to `output/` beside the application.

Pre-rendered HTML is used only for document requests. Navigation requests that
ask for JSON still run the route and receive their data and chunk URL. `HEAD`
responses retain the encoding and length of `GET` without sending its body.

`prerender` in the manifest moves that into the server: `true` holds every fixed route, and a list holds the paths named. Each one is rendered on the first request that needs it and answered from memory afterwards, so a page whose probe reads a database stops touching it. Development never holds anything, and a path that fails to render is remembered as a failure and rendered normally rather than retried on every request. This trades freshness for work, so it belongs on pages that do not change between deploys.

`lunar bench --http URL` drives a running server over keep-alive connections and reports requests a second and the latency spread. On the same machine as the server, with 32 keep-alive connections and the client in one process of its own, the example application answers about 4,200 requests a second at a median of 7.5 ms, 8.7 ms at the 95th percentile and 11.4 ms at the 99th. Both sides are competing for the same cores, so that is a floor rather than a ceiling. Run the server with `RATE_LIMIT=0` for a load test, since the rate limiter exists to stop exactly what a load test does.

The takeover is also measured, against the table DOM the tests use rather than a browser. Claiming is not faster than rebuilding there, and is not meant to look like it: in a table DOM a node costs a table. What claiming buys is the node itself, and in a browser a created node also costs layout and paint, which that measurement cannot capture.

The HTTP server is a single process with a single thread. Each connection runs in a coroutine, yields whenever its socket would block, and is resumed by a `socket.select` loop, so one thread serves many keep-alive connections. Read, keep-alive, and write deadlines are enforced by the loop itself rather than only when a client sends something, so a connection that goes quiet is dropped rather than holding its slot. The number of connections and the number of requests per connection are both bounded, and a connection past the limit is closed on accept.

An endpoint can answer with a stream instead of a string: `response.stream(function(write) ... end)` is sent with `Transfer-Encoding: chunked`, one chunk per `write`, and the connection is reused afterwards like any other. The writer yields whenever the socket would block, so a slow reader costs a coroutine rather than the loop. A producer that fails partway through has already sent part of a body that cannot be taken back, so the connection is dropped without the terminating chunk, which is what tells the client the body is incomplete. A client that speaks HTTP/1.0 gets the same bytes collected into one body with a `Content-Length`, and so does a `HEAD`, which announces the framing and sends nothing. Pages are not streamed: `<lunar:head>` is collected while the body renders, so the `<head>` is only known once the body is done. An app frozen for Workers collects every stream into a string, because the bridge hands the platform one response.

A probe or an endpoint that blocks blocks the whole loop, because there is one thread to block. Work that waits should be kept off the request path, and an application that needs more than one core should run more than one process behind a proxy. `spec/concurrency_spec.lua` drives many concurrent connections, slow clients, partial writes, timeouts, and the connection limits through the real loop with a substituted socket library.

## Lua in WebAssembly

A directory called `wasm/` beside `orbit/` holds plain Lua files whose functions Lunar compiles to WebAssembly. The compiler is in `lunar/wasm/`, written in Lua with nothing under it: `encode.lua` writes the binary format, `module.lua` assembles the sections, `parse.lua` reads the subset of Lua this covers, and `compile.lua` emits the instructions. No toolchain, no vendored binary, no build step — a part is compiled in memory and cached like a component.

```lua
-- wasm/geometry.lua
function area(radius)
  return 3.141592653589793 * radius ^ 2
end

local function term(index)
  return 1 / (index * index)
end

function basel(count)
  local total = 0
  for index = 1, count do
    total = total + term(index)
  end
  return total
end
```

A `function` is exported from its part; a `local function` stays inside it. The subset covers arithmetic with `+ - * / // % ^`, comparisons, `and`, `or`, `not`, `if`, `while`, a numeric `for` with a literal step, `break`, `local`, assignment, calls, `..`, `#`, table constructors, indexing with `t[k]` and `t.k`, functions as values, closures over the variables around them, several returns, a trailing `...`, and `math.abs`, `math.ceil`, `math.floor`, `math.max`, `math.min`, `math.sqrt` and `math.trunc`. `//` and `%` floor the way Lua does, so `-7 % 3` is `2` and not `-1`. `^` is the one thing with no instruction behind it, so a part that raises a power imports `pow` from the host. Coroutines, methods with `:`, `goto` and the standard library beyond `math` are refused at compile time, with the file and the line.

Every value is one `f64`, because a Lua number already is one. The others ride in the quiet NaNs a double is not otherwise using: a tag and a 32-bit payload, which is `nil`, a boolean, or an address in the memory. Arithmetic therefore costs nothing extra, and `if v then` is false for exactly `nil` and `false`, as in Lua. A comparison used as a value becomes a real boolean rather than a `1`.

Strings are bytes in that memory with their length in front. A literal is written into the module's data section at compile time, so reaching for it costs no allocation, and the same literal appears once however often it is written. `..` allocates and copies, `==` compares by content, `#` is the length, and `<`, `<=`, `>` and `>=` compare byte by byte as Lua does. A number concatenated onto a string is written the way Lua writes it, to fourteen significant digits with the exponent where Lua puts one, so `1/3` is `0.33333333333333` and `1e20` is `1e+20`. The one difference is the whole numbers: the subset has no integer subtype, every number being a float, so `3` is written `3` rather than `3.0`.

A table has an array part for the keys `1..n` and an open-addressed hash part for the rest, which grows and rehashes as it fills. `{ 1, 2, name = "lunar" }`, `t[k]`, `t.k`, `t[k] = v` and `#t` all work. Assigning `nil` to a key stores the nothing but keeps the slot. `setmetatable`, `getmetatable`, `rawget`, `rawset` and `type` are there, and a table consults its metatable's `__index` and `__newindex`, each of which may be a table or a function. The metamethods for arithmetic, comparison and calling are not consulted.

A function is a value: `local f = function(x) ... end`, `local g = area`, `f(2)`, a function in a table. A closure keeps the variables around it rather than copies of them, so the counter below counts, and a variable a closure captures lives in the memory rather than in a register. Every function a part compiles gets a slot in one table the host shares between parts, which is how a value made in one part can be called from another.

```lua
function counter(start)
  local total = start
  local function bump(by)
    total = total + by
    return total
  end
  bump(1)
  bump(2)
  return total
end
```

A function can return several values and a caller can take them: `return total, mean` and `local sum, average = stats(...)`. The extra values travel through a small fixed region of the memory, which is why there are at most eight of them, and why only the first crosses from one part to another. A trailing `...` collects the arguments a named function was given beyond its own; it is read as `{...}`, which is a fresh table, or as `select("#", ...)`, and anything else is refused rather than quietly meaning something slightly different. A function value cannot take `...`, and neither can one a part exports, since the host calling it has no way to pass the extras: a `local function` takes them and an exported one calls it.

**There is no garbage collector**, and `heap.mark()` with `heap.release(mark)` is what there is instead. The allocator moves a pointer forward; `heap.mark` reads it and `heap.release` puts it back, which frees everything allocated in between at once. It is an arena, with an arena's contract: nothing allocated after the mark may be held once it is released. For work that computes, allocates while it computes and returns a number, that is the whole story:

```lua
function churn(rounds)
  local round = 1
  local last = 0
  while round <= rounds do
    local mark = heap.mark()
    local scratch = { round }
    last = scratch[1]
    heap.release(mark)
    round = round + 1
  end
  return last
end
```

A tracing collector would need to find the live values, and they sit in WebAssembly locals, which a module cannot look at. Giving it roots means moving every value that might be a reference into a shadow stack in the memory, which costs every function something, numeric ones included; that is the price, and it has not been paid here. Coroutines are a harder no: the MVP WebAssembly this compiles to cannot switch stacks at all, so they would mean either a transform of every function into a state machine or a toolchain pass, and the honest place for a coroutine is still the Lua that runs in the Lua 5.4 VM, which may call into a part.

The memory itself comes from the host: the loader makes one `WebAssembly.Memory`, hands it to every part, and the heap grows into it. A part that needs strings or tables imports Lunar's own runtime part, which carries the allocator, the string and the table operations, and is itself compiled from Lua by the same compiler. It is emitted only when something needs it, loaded before the parts that do, and its exports are not names an application can ask for.

**Every file is its own part, and a part is fetched only when something calls into it.** A part that calls a function another part exports imports it by name, which makes the dependency real rather than declared: `lunar wasm` prints it, and the browser loads the chain in order. A part nothing has asked for is never downloaded.

```text
$ lunar wasm examples/tranquility/wasm/*.lua
geometry.wasm       129 bytes  exports area hypotenuse
series.wasm         265 bytes  exports basel rings  needs geometry
```

The server compiles the parts on demand and serves them from `/_lunar/wasm/`, with `index.json` saying which part exports what and what each one needs. An app frozen for Workers writes the same files into `public/`, where the platform serves them: the Worker never compiles WebAssembly, the browser does, so the two targets load the identical bytes.

In a component, `wasm(name, on_ready)` asks for a function and is handed it once its part has arrived. What comes back is read for you: a number stays a number, and `nil`, a boolean or a string arrives as itself. Loading is a fetch, so the answer comes in a callback rather than in place, and a page renders on the server without any of it.

```lunar
<script>
  area_of = nil

  local function measure()
    wasm("area", function(area) area_of = area(3) end)
  end
</script>

<button wasm:preload={"area"} on:click={measure}>measure</button>
<output>{area_of or "—"}</output>
```

`wasm:preload={"area"}` warms the part before the click: the element asks for it when the pointer arrives, when focus lands on it, or when a finger touches it, once, and the click then finds it already there. The directive renders nothing — it is behaviour, not markup, so the server's HTML and the browser's agree.

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
lunar workers examples/tranquility
cd examples/tranquility/.lunar/workers
bun install
bunx wrangler dev
bunx wrangler deploy
```

The generated deployment contains the application and its compiled routes in `src/app.lua`, the JavaScript entry point in `src/worker.ts`, compatibility modules in `src/fs-stub.cjs` and `src/absent.cjs`, static assets in `public/`, and the Worker configuration in `wrangler.jsonc`.

The packaged Lua application does not read files or open sockets at runtime. Cloudflare handles incoming requests and static assets, while the Lua 5.4 WebAssembly runtime executes the compiled application. The bridge exchanges requests and responses as JSON, so responses are buffered as strings. Rate limiting is scoped to each Worker isolate.

The Workers bundle is tested separately from the normal server, including execution with filesystem access removed, to check that both targets produce the same page output.

## Editor support

The VS Code extension in `editors/vscode/` provides syntax highlighting for Lua, HTML, and CSS in `.lunar` files. It uses Lunar's compiler for diagnostics, supports definition lookup for imported components, and can display the Lua generated from a component.

To validate and package the extension:

```sh
cd editors/vscode
bun run check
bunx @vscode/vsce package
code --install-extension lunar-lang-0.1.0.vsix
```

## CLI

The command-line interface is available through `lunar`:

```sh
lunar dev [app]
lunar build [app]
lunar map [app]
lunar analyze [app]
lunar prerender [app]
lunar compile file
lunar wasm file...
lunar bench [app]
lunar bench --http URL
lunar workers [app]
lunar spec
```

`dev` starts the development server, `build` compiles the application's components to check for errors, and `map` prints the discovered routes. `compile` writes the generated Lua for a component to standard output and `wasm` compiles Lua files into wasm parts, reporting what each one exports and needs, writing them to `WASM_OUT` when that is set. `analyze` reports what a browser downloads for the application and what is inside the bundle, `prerender` writes the fixed routes to HTML, `bench` measures compiling, rendering, the takeover, and the download, `workers` creates a Cloudflare Workers deployment, and `spec` runs the test suite.

## Formatting

Everything in the repository that is not Lua is formatted with Prettier: Markdown, YAML, JSON, CSS, HTML, and JavaScript. There is no package manifest at the root and nothing to install, since the version is named at the point of use:

```sh
bunx prettier@3.9.10 --write .
bunx prettier@3.9.10 --check .
```

The settings are in `.prettierrc`. Lua files are listed in `.prettierignore`, since Prettier has no Lua support; Lua in this repository uses two-space indentation, `snake_case` names, and no comments. The continuous integration workflow runs the check alongside the test suite.

## Repository structure

The implementation is under `lunar/`. Shared utilities for JSON, HTML escaping, URLs, MIME types, and files are in `lunar/core/`. The parser, CSS scoping, and code generation are in `lunar/compiler/`, while reactivity, server rendering helpers, and DOM handling are in `lunar/runtime/`.

Routing, rendering, the browser bundle, and deployment targets live under `lunar/site/`, with Cloudflare Workers support in `lunar/site/targets/`. The HTTP server, request handling, static files, and security are in `lunar/http/`, and the WebAssembly compiler is in `lunar/wasm/`. Example applications are in `examples/`, tests are in `spec/`, editor integrations are in `editors/`, and the project assets are in `brand/`. The site published at lunar.estelaz.com is in `website/`: it is a Lunar application like any other, built against the framework beside it rather than a release, so it is also a standing test that the framework works.

## Versions

The number is read the way Lua's own is. `1.0` is the series and the last number is the release within it, so `1.0.0` is the first release of Lunar 1.0 and `1.0.1` would be the same framework with its mistakes corrected. A release that changes what a component or an application means raises the series, the way Lua 5.3 and Lua 5.4 are different languages rather than different builds of one. `lunar.VERSION` carries the number, `lunar help` prints it, and a signed tag such as `v1.0.0` marks it in the repository.

## Testing and development status

The test suite contains 193 tests. It compares the HTML generated by the server renderer with the markup serialized from the Lua-based DOM renderer, checks the browser bundle against data produced by the server, and tests the packaged Workers application without filesystem access. It also parses the server's own markup the way a browser would and runs the takeover against it, for every route of the example application, asserting that each element afterwards is the one the server sent. The connection scheduling is tested by driving concurrent connections through the real server loop.

The compiler, component model, reactivity, routing, HTTP server, hydration, browser navigation, security defaults, keyed iteration, named slots, Workers target, and VS Code extension are implemented. An endpoint can stream a chunked response. `{#await}` and built-in form actions are not supported, and a page is always sent with a `Content-Length`: the runtime has no asynchronous primitive to await, and a page's `<head>` is only known once its body has rendered. Server-side form handling can be implemented through `api.lua` endpoints.

The codebase uses Lua 5.4, two-space indentation, `snake_case` names, and one returned table per module. Tests follow the `name_spec.lua` naming convention. Apart from LuaSocket for socket access, the framework's HTTP handling, compiler, runtime, and supporting modules are implemented in the repository.
