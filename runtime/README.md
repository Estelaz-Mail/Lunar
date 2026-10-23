# Lunar Lua 5.4 runtime

Lunar runs the official Lua 5.4.9 VM in WebAssembly. `bridge.c` exposes the Lua
stack and installs a `js` module; `runtime/bridge.ts` owns JavaScript
values, callbacks and the Wasm instance. No JavaScript is generated from Lua
source. The browser and the generated Cloudflare Worker use the same binary.

The Lua parser, bytecode VM, garbage collector, coroutines and standard
libraries are upstream Lua. This is a Lunar embedding of Lua, not a new
implementation of the language. Integer values use Lua's signed 64-bit type;
values outside JavaScript's safe integer range cross the bridge as `BigInt`.

## Resources and loading

The browser receives the `boot` endpoint, loads the `bridge` endpoint, fetches `lua54.wasm`
and the application's `moonlight.lua`. Resources have versioned URLs and
independent cache entries. Their URL revision includes the integrity manifest,
so changing code invalidates caches even when the application version stays the
same. A server-only application emits no runtime scripts.
Compiled application functions under `wasm/` remain separate Wasm modules,
requested only when referenced through `wasm(name, callback)`.

The Lua engine is currently a single Wasm module including the parser and
standard libraries. Per-library lazy loading is not implemented. Production
applications split components into route chunks, named by SHA-256, and keep
shared components in moonlight. `split = false` disables this, and imports that
cannot be resolved statically retain the complete bundle. Concurrent navigation
requests share one chunk download and execution. Splitting application code
does not make the VM smaller.
The current engine is about 196 KiB raw and 90 KiB with gzip; the bridge adds
about 3 KiB with gzip. This is larger with gzip than the runtime it replaces.

## Integrity boundary

The HTML carries SHA-256 hashes for the bootstrap, bridge, VM, moonlight bundle,
Wasm index and every application Wasm part. The bootstrap and bridge use browser
Subresource Integrity. The VM, Lua source, index and Wasm parts are fetched and
verified with Web Crypto before compilation, parsing or execution. Missing
hashes, changed bytes and redirects fail closed. The Wasm loader has no fallback
to an unchecked fetch.

The trusted root is the HTML document delivered by the application over HTTPS.
This protects the listed executable resources against replacement while that
root remains trusted. It does not authenticate a compromised document/server,
verify arbitrary local files, or establish a signed-release trust chain for the
installer. Dynamic route data and images/fonts are not executable runtime
modules and are outside this manifest. Precompiled Worker modules are trusted
as part of the deployed package, not fetched from an untrusted endpoint.

## Host contract

`require("js")` provides `global`, `null`, `new(constructor, ...)` and
`createproxy(value, type)`. JavaScript properties support Lua indexing and
assignment. Assigning `nil` deletes a property. `null` is distinct from `nil`.
Call a JavaScript method with `object:method(...)`, or pass its receiver
explicitly as the first argument. JavaScript callbacks call Lua with their
arguments, without adding a receiver. Functions preserve identity so an event
listener can be removed using the same Lua function.

Lua objects retain JavaScript objects through userdata. Lua garbage collection
releases those handles. JavaScript proxies retain Lua registry references until
their JavaScript finalizer runs. `runtime.close()` explicitly frees the Lua
state and invalidates callbacks. JavaScript exceptions become Lua errors inside
protected calls; Lua failures become JavaScript errors at the host boundary.

The VM includes the standard libraries, but host capabilities follow the
platform. There is no native filesystem, subprocess execution, terminal input
or native C-module loading in browsers or Workers. Standard I/O writes to the
configured logging callbacks and stdin is empty. File operations fail rather
than accessing the user's filesystem. Use browser/Worker APIs through the host
bridge for platform services. Access to host APIs means this embedding is not
a sandbox for untrusted application Lua.

The document CSP permits `'wasm-unsafe-eval'` to compile WebAssembly. It does
not permit JavaScript `'unsafe-eval'`. A host which imports a precompiled Wasm
module, such as Cloudflare Workers, passes that module to `LuaRuntime.create`.

## Rebuilding the distributed binary

Users of Lunar do not need a compiler. The binary is checked in alongside its
source and license notices. The host sources are typed TypeScript. `prepare.ts`
uses Bun to prepare executable source inside JSON artifacts in `static/runtime/`.
The server decodes those artifacts and serves extensionless module endpoints
with the script MIME type. There are no stripped copies disguised as TypeScript
source files and no `.js` or `.mjs` output.

Maintainers rebuild with Bun 1.3.14+, Emscripten 5.0.3, curl,
SHA-256 tools and tar:

```sh
sh runtime/build.sh
bun run --cwd website typecheck
bun test spec/lua54.test.ts
bin/lunar spec
```

The script downloads Lua 5.4.9 from lua.org and verifies SHA-256
`2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6`.
Emscripten links a standalone Wasm reactor with Wasm exception handling for
Lua's protected calls. There is no generated Emscripten JavaScript glue.
The embedding requires Wasm exception support, ES modules, `BigInt`, `WeakRef`
and `FinalizationRegistry` in the host.

Tests cover selected Lua 5.4 features and bridge behavior. Passing them does not
constitute a claim of complete Lua conformance or full browser compatibility.
