# Vendored

`fengari-web.js` is [Fengari](https://fengari.io) — the Lua 5.4 virtual
machine, in JavaScript — which is what runs the browser half of a Lunar app.
It is checked in rather than fetched because this framework has no build step
and no package manager: a file an app depends on at runtime is a file in the
repository.

Served as `/_lunar/fengari.js`. Nothing in `lunar/` imports it; the document
shell links it, and `lunar/runtime/dom.lua` talks to the browser through the
`js` module Fengari provides.
