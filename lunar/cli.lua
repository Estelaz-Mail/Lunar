--- The CLI. `bin/lunar` sets the module path and calls this.

package.path = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/lunar/cli%.lua$") or ".")
  .. "/?.lua;" .. package.path

local lunar = require("lunar")

local cli = {}

local function fail(message)
  io.stderr:write("lunar: ", message, "\n")
  os.exit(1)
end

local USAGE = [[
lunar ]] .. lunar.VERSION .. [[ — a framework in Lua

  lunar dev [app]          serve an app on :3000, compiling on demand
  lunar build [app]        compile everything once and report what failed
  lunar map [app]          print the route table as it was discovered
  lunar compile <file>     print the Lua a component compiles to
  lunar workers [app]      generate a Cloudflare Workers deploy directory
  lunar spec [name...]     run the tests

`app` is a directory with an orbit/ tree in it; it defaults to the working
directory. PORT and HOST are read from the environment.
]]

function cli.help()
  io.write(USAGE)
end

local function app_root(argument)
  local root = argument or os.getenv("LUNAR_APP") or "."
  local fs = require("lunar.core.fs")
  if not fs.is_directory(require("lunar.core.fs").join(root, "orbit")) then
    -- `is_directory` is a guess on some systems; a missing tree is reported
    -- when the routes come back empty instead.
  end
  return (root:gsub("/+$", ""))
end

function cli.dev(argument)
  local root = app_root(argument)
  local app = lunar.app({ root = root, dev = true })
  if #app.routes == 0 then
    fail(string.format("%s has no orbit/ tree (looked in %s/orbit)", root, root))
  end
  io.write(string.format("lunar %s — %d routes in %s/orbit\n",
    lunar.VERSION, #app.routes, root))
  lunar.serve({
    root = root,
    dev = true,
    host = os.getenv("HOST") or "127.0.0.1",
    port = tonumber(os.getenv("PORT")) or 3000,
  })
end

function cli.serve(argument)
  local root = app_root(argument)
  lunar.serve({
    root = root,
    dev = false,
    host = os.getenv("HOST") or "0.0.0.0",
    port = tonumber(os.getenv("PORT")) or 3000,
  })
end

--- There is nothing to build, which is the point: this compiles everything so
-- a mistake is found now rather than on the first request, and assembles the
-- moonlight bundle so its size is known.
function cli.build(argument)
  local root = app_root(argument)
  local fs = require("lunar.core.fs")
  local bundle = require("lunar.site.bundle")

  local app = lunar.app({ root = root, dev = false })
  local failures = 0
  local compiled = 0

  for _, relative in ipairs(fs.files(root)) do
    if relative:match("%.lunar$") then
      local path = fs.join(root, relative)
      local def, err = app.cache:get(path)
      if def then
        compiled = compiled + 1
        io.write("  ok    ", path, "\n")
      else
        failures = failures + 1
        io.write("  FAIL  ", path, "\n        ", tostring(err):gsub("\n", "\n        "), "\n")
      end
    end
  end

  local source, bundle_error = bundle.build(app)
  if not source then
    failures = failures + 1
    io.write("  FAIL  the moonlight bundle\n        ", tostring(bundle_error), "\n")
  else
    io.write(string.format("\n%d components, %d routes, %.1f KB of moonlight bundle\n",
      compiled, #app.routes, #source / 1024))
  end

  if failures > 0 then
    io.write(string.format("%d failed\n", failures))
    os.exit(1)
  end
end

function cli.map(argument)
  local root = app_root(argument)
  local app = lunar.app({ root = root, dev = true })
  if #app.routes == 0 then
    fail(string.format("%s has no orbit/ tree", root))
  end

  io.write(string.format("%d routes in %s/orbit, most specific first\n\n",
    #app.routes, root))
  for _, route in ipairs(app.routes) do
    local kinds = {}
    if route.page then kinds[#kinds + 1] = "page" end
    if route.endpoint then kinds[#kinds + 1] = "endpoint" end
    io.write(string.format("  %-28s %s\n", route.id, table.concat(kinds, " + ")))
    for _, level in ipairs(route.levels) do
      local parts = {}
      if level.component then parts[#parts + 1] = level.component end
      if level.probe then parts[#parts + 1] = level.probe end
      io.write("      ", table.concat(parts, "  +  "), "\n")
    end
    if route.eclipse then io.write("      eclipse: ", route.eclipse, "\n") end
  end
end

--- Freezes the app into a directory `wrangler` can deploy.
--
-- The app becomes one Lua file with no filesystem access, next to the
-- JavaScript entry point that runs it on Fengari. The same shape a Rust Worker
-- has — an artifact the edge runtime executes and a small entry that hands it
-- the request — with no WebAssembly toolchain in the way.
function cli.workers(argument)
  local root = app_root(argument)
  local workers = require("lunar.site.targets.workers")
  local app = lunar.app({ root = root, dev = false })
  if #app.routes == 0 then
    fail(string.format("%s has no orbit/ tree", root))
  end

  local out = os.getenv("LUNAR_OUT")
  local result, err = workers.generate(app, { out = out, name = os.getenv("LUNAR_NAME") })
  if not result then fail(tostring(err)) end

  local total = 0
  for _, file in ipairs(result.files) do
    total = total + file.bytes
    io.write(string.format("  %-26s %s\n", file.path,
      file.files and string.format("%d files", file.files)
        or string.format("%.1f KB", file.bytes / 1024)))
  end

  io.write(string.format([[

%d routes, %.1f KB in all, in %s

  cd %s
  npm install
  npx wrangler dev        # http://localhost:8787
  npx wrangler deploy
]], #app.routes, total / 1024, result.out, result.out))
end

function cli.compile(path)
  if not path then fail("compile needs a file: lunar compile orbit/page.lunar") end
  local compiler = require("lunar.compiler")
  local util = require("lunar.core.util")
  local source = util.read_file(path)
  if not source then fail(path .. ": no such file") end
  local ok, generated = pcall(compiler.compile, source, { path = path })
  if not ok then fail(tostring(generated)) end
  io.write(generated, "\n")
end

local command = ...
local argument = select(2, ...)

local handler = cli[command]
if not handler or command == "help" then
  cli.help()
  os.exit(command == "help" and 0 or 1)
end

handler(argument)
