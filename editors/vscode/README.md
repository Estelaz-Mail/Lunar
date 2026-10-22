# Lunar for VS Code

Editor support for [Lunar](https://github.com/Glazastyy/Lunar): a web
framework in Lua, where the same components render on the server and run in
the browser.

## What it does

**Highlighting that knows what a `.lunar` file is.** The `<script>` is Lua, the
`<style>` is CSS, and every expression in the template is Lua too — inside
`{count}`, inside `{#each items as item}`, inside `on:click={…}` and
`attr={…}`. A capitalised tag is coloured as a component, a directive is
coloured as a directive, and `{@html …}` stands out, because it is the one way
past escaping.

**Diagnostics from the compiler itself.** There is no second implementation of
the parser here: the extension runs `lunar compile` on the buffer and turns
what it says into squiggles, so the editor and the command line can never
disagree about what is an error. Unsaved buffers are checked through a
temporary file, so the squiggles are live rather than one save behind.

**Lunar: Show the Lua this component compiles to.** The generated module opens
beside the component. It is the first thing to reach for when a template does
not do what it reads like — and the `<script>` keeps its original line numbers
inside it, which is why a runtime error points back at the component.

**The commands you would otherwise type:** the dev server, the build check,
the orbit, the tests.

**It carries the framework, and prefers yours.** The extension ships a copy of
Lunar inside it, so it has a compiler even with no checkout anywhere — but it
looks for yours first: `lunar.path` if you set it, then `bin/lunar` in the
folder you have open and in every parent of it, then `lunar` on your `PATH`,
and only then its own copy. Working on Lunar itself therefore gives you
diagnostics from the compiler you are editing, not from a frozen one. What it
cannot carry is the interpreter: the copy runs under whatever Lua 5.4 is on
your `PATH`, or the one `lunar.lua` points at. What was found is in the status bar while a
`.lunar` file is open, with the version it reported. When it cannot be found,
the warning says how many places were tried, the output channel lists them one
by one, and **Lunar: Locate the CLI** opens a file picker that writes
`lunar.path` for you. A CLI that is there but not executable, and one that
cannot start because Lua is missing, say exactly that rather than failing as a
compiler error. **Lunar: CLI status** asks again and reports what it found.

**Go to definition** on `import("./Card.lunar")`, resolved the way the compiler
resolves it.

**Snippets** for Lunar's own shapes — a component, a `page`, a `shell`, a
`probe`, an `api`, an `eclipse` — and for `{#if}`, `{#each}`, `props`,
`derived`, `on_rise` and `event.fail`.

## Settings

| Setting                      | What it is                                                                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `lunar.path`                 | Path to the CLI. Empty: `bin/lunar` in the folder you have open or any parent, then `lunar` on `PATH`, then the copy inside the extension. |
| `lunar.app`                  | The app directory. Empty: the nearest ancestor with an `orbit/` in it.                                                                     |
| `lunar.diagnostics.run`      | `onType` (default), `onSave`, `off`.                                                                                                       |
| `lunar.diagnostics.debounce` | Milliseconds after the last keystroke before re-checking.                                                                                  |
| `lunar.lua`                  | The Lua 5.4 interpreter to run under. Empty: `lua5.4`, then `lua`, from `PATH`.                                                            |

## Running it from a checkout

```sh
code --extensionDevelopmentPath="$PWD" ../../examples/tranquility
npm run check          # the grammar, the manifest and the CLI search, without an editor
npm run stage          # copy the framework into runtime/, which the package carries
npm run package        # a .vsix, with @vscode/vsce
```

There is no compile step: the extension is plain JavaScript and the manifest
points straight at `src/extension.js`. That is on purpose — Lunar's own rule is
that there is no build step, and an extension that needed `tsc` before it could
run would be the first exception to it.

`npm run check` is the test suite. It cannot assert on colours, but it catches
the two ways a grammar actually breaks — a regular expression that does not
compile, and an `include` pointing at a rule that is not there — and the ways a
manifest breaks: a command nothing registers, a setting nothing reads, a path
that is not on disk.

## One thing to know

VS Code gives a file one comment style, and a `.lunar` file has two. The line
comment is `--`, which is right inside the `<script>` where commenting out code
is what you want; the block comment is `<!-- -->`, which is right in the
template. Toggling a line comment in the template will insert `--`, which the
template will render as text.
