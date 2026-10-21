--- The two bundles: the moonlight, and the frozen app.
--
-- **Moonlight** is the app as it reaches the browser. Fengari has no loader
-- that can fetch a module over HTTP, so everything the browser needs arrives
-- in one file: the runtime modules, every compiled component in the app, and a
-- registry mapping route ids to components. Each
-- is wrapped in `package.preload`, which is the one hook `require` consults
-- before it goes looking at a filesystem the browser does not have.
--
-- The second bundle, `bundle.server`, is the same idea pointed the other way:
-- the whole app frozen into one file for a platform with no filesystem.
--
-- Both are assembly, not bundling: no transform, no minification, no tree
-- shaking. The sources go in as they are, which means a stack trace in the
-- browser names the same file and the same line as one on the server.

local fs = require("lunar.core.fs")
local json = require("lunar.core.json")
local resolve = require("lunar.compiler.resolve")
local util = require("lunar.core.util")

local bundle = {}

-- The moonlight runtime, in dependency order. Order does not matter to
-- `preload`, but it does to anyone reading the bundle.
local MODULES = {
  "lunar/core/util.lua",
  "lunar/core/html.lua",
  "lunar/core/json.lua",
  "lunar/compiler/resolve.lua",
  "lunar/runtime/signal.lua",
  "lunar/runtime/scope.lua",
  "lunar/runtime/ssr.lua",
  "lunar/runtime/dom.lua",
  "lunar/runtime/component.lua",
  "lunar/site/moonlight.lua",
  "lunar/site/boot.lua",
}

local function module_name(path)
  -- `lunar/init.lua` is the module `lunar`, not `lunar.init`: that is what
  -- `require` does with a directory's init file, and an app that writes
  -- `require("lunar")` has to find the same thing in a bundle.
  return (path:gsub("%.lua$", ""):gsub("/", "."):gsub("%.init$", ""))
end

--- Wraps a source in a `package.preload` entry.
--
-- The source is put in a long bracket of a level that does not occur in it, so
-- a component containing `]]` cannot end the wrapper early, and it is `load`ed
-- with its own chunk name so errors keep pointing at the real file.
local function preload(name, source, chunk_name)
  local level = ""
  while source:find("]" .. level .. "]", 1, true) do level = level .. "=" end
  return string.format(
    "package.preload[%q] = assert(load([%s[\n%s]%s], %q))",
    name, level, source, level, "@" .. chunk_name)
end

--- Every `.lunar` file in the app. All of them, not only the routes: a
-- component a page imports has to be there too, and finding out which by
-- following imports would mean parsing what the compiler already parsed.
local function app_components(app)
  local out = {}
  for _, relative in ipairs(fs.files(app.root ~= "" and app.root or ".")) do
    if relative:match("%.lunar$") then
      out[#out + 1] = fs.join(app.root, relative)
    end
  end
  table.sort(out)
  return out
end

--- The route table the client needs: a route id, and the components that draw
-- it, outermost first.
local function route_map(app)
  local map = {}
  for _, route in ipairs(app.routes) do
    local paths = {}
    for _, level in ipairs(route.levels) do
      if level.component then paths[#paths + 1] = level.component end
    end
    if #paths > 0 then map[route.id] = paths end
  end
  return map
end

--- Builds the bundle. Returns the source, or nil and the first compile error:
-- a component that does not compile must break the build, not the page.
function bundle.build(app)
  if app.bundle_cache and not app.dev then
    return app.bundle_cache
  end

  local parts = {
    "-- Assembled by lunar. Every module the browser half needs, in one file,",
    "-- because Fengari cannot fetch one.",
  }

  for _, relative in ipairs(MODULES) do
    local path = fs.join(app.framework, relative)
    local source = util.read_file(path)
    if not source then return nil, path .. " is missing from the framework" end
    parts[#parts + 1] = preload(module_name(relative), source, relative)
  end

  local components = {}
  for _, path in ipairs(app_components(app)) do
    local def, generated = app.cache:get(path)
    if not def then return nil, generated end
    components[path] = resolve.module_name(path)
    parts[#parts + 1] = preload(resolve.module_name(path), generated, path)
  end

  local registry = {
    root = app.root,
    components = components,
    routes = route_map(app),
  }

  parts[#parts + 1] = string.format(
    "package.preload[%q] = function() return %s end",
    "lunar.app.registry", bundle.literal(registry))

  -- Starting is wrapped, and the registry is returned.
  --
  -- The wrapper is not for the specs' benefit: a failure in the browser half
  -- should print something a person can act on, not vanish into Fengari's
  -- error path. Returning the registry is what lets `spec/bundle_spec.lua`
  -- load this very file in a bare Lua state and mount a route against the
  -- mock DOM, which is how the browser half is tested without a browser.
  parts[#parts + 1] = table.concat({
    'local registry = require("lunar.app.registry")',
    'local started, failure = pcall(function()',
    '  require("lunar.site.boot").start(registry)',
    'end)',
    'if not started then print("lunar: the client half did not start: "'
      .. ' .. tostring(failure)) end',
    'return registry',
  }, "\n")

  local source = table.concat(parts, "\n\n") .. "\n"
  app.bundle_cache = source
  return source
end

--- A Lua literal for a table of strings. The registry is data the server
-- computed, not data from a request, but it is still written as a literal
-- rather than interpolated, so a path with a quote in it cannot become code.
function bundle.literal(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if type(value) ~= "table" then return "nil" end

  local pieces = {}
  local array = #value > 0
  if array then
    for _, item in ipairs(value) do pieces[#pieces + 1] = bundle.literal(item) end
  else
    for _, key in ipairs(util.keys(value)) do
      pieces[#pieces + 1] = string.format("[%q] = %s", tostring(key), bundle.literal(value[key]))
    end
  end
  return "{ " .. table.concat(pieces, ", ") .. " }"
end

-- The server runtime, for a platform that runs the app itself rather than
-- serving what a socket hands it. The compiler is deliberately not here: a
-- frozen app has nothing left to compile, and leaving it out is most of the
-- difference between a small bundle and a large one.
local SERVER_MODULES = {
  -- `lunar` itself, because an app may ask it for its version.
  "lunar/init.lua",
  "lunar/core/util.lua",
  "lunar/core/html.lua",
  "lunar/core/json.lua",
  "lunar/core/url.lua",
  "lunar/core/mime.lua",
  -- `fs` is here for the two helpers that are pure string work; the one
  -- function that shells out is never called by a frozen app.
  "lunar/core/fs.lua",
  "lunar/core/base64.lua",
  "lunar/crypto/sha256.lua",
  "lunar/compiler/resolve.lua",
  "lunar/runtime/signal.lua",
  "lunar/runtime/scope.lua",
  "lunar/runtime/ssr.lua",
  "lunar/runtime/dom.lua",
  "lunar/runtime/component.lua",
  "lunar/http/request.lua",
  "lunar/http/response.lua",
  "lunar/http/router.lua",
  "lunar/http/static.lua",
  "lunar/http/security.lua",
  "lunar/http/ratelimit.lua",
  "lunar/site/errors.lua",
  "lunar/site/routes.lua",
  "lunar/site/render.lua",
  "lunar/site/app.lua",
  "lunar/site/worker.lua",
}

--- The module name a route's `.lua` file is registered under.
local function server_module_name(path)
  return "lunar.app.module:" .. path
end

--- The name an app's own library module is required by.
--
-- On a server these are found through `package.path`, which a frozen app does
-- not have, so `lib/posts.lua` is preloaded as `posts` — the name the `require`
-- in a probe already uses.
local function library_module_name(root, path)
  local relative = path
  local prefix = (root ~= "" and root or ".") .. "/lib/"
  if relative:sub(1, #prefix) == prefix then relative = relative:sub(#prefix + 1) end
  return (relative:gsub("%.lua$", ""):gsub("/", "."))
end

--- Everything in the app that is Lua rather than a component: the probes, the
-- endpoints, and the `lib/` they require.
local function app_modules(app)
  local out = {}
  for _, relative in ipairs(fs.files(app.root ~= "" and app.root or ".")) do
    if relative:match("%.lua$") then
      local path = fs.join(app.root, relative)
      local routes_lib = require("lunar.site.routes")
      if relative:match("^orbit/") and routes_lib.FILES[fs.basename(relative)] then
        out[#out + 1] = { path = path, name = server_module_name(path) }
      elseif relative:match("^lib/") then
        out[#out + 1] = { path = path, name = library_module_name(app.root, path) }
      end
    end
  end
  return out
end

--- The route table, flattened into something a literal can hold.
local function route_manifest(app)
  local out = {}
  for index, route in ipairs(app.routes) do
    local levels = {}
    for position, level in ipairs(route.levels) do
      levels[position] = {
        component = level.component,
        probe = level.probe,
        page = level.page or false,
      }
    end
    out[index] = {
      id = route.id,
      directory = route.directory,
      segments = route.segments,
      page = route.page,
      page_probe = route.page_probe,
      endpoint = route.endpoint,
      eclipse = route.eclipse,
      levels = levels,
    }
  end
  return out
end

--- The whole app as one Lua file: the runtime, every component, every load,
-- the route table, and a `fetch` to call. Nothing in it reads a file.
function bundle.server(app, options)
  options = options or {}
  local parts = {
    "-- Assembled by lunar. A whole app in one file: the runtime, the",
    "-- components, the loads and the route table. Nothing here opens a file,",
    "-- because the platform this is for has none.",
  }

  for _, relative in ipairs(SERVER_MODULES) do
    local path = fs.join(app.framework, relative)
    local source = util.read_file(path)
    if not source then return nil, path .. " is missing from the framework" end
    parts[#parts + 1] = preload(module_name(relative), source, relative)
  end

  local components = {}
  for _, path in ipairs(app_components(app)) do
    local def, generated = app.cache:get(path)
    if not def then return nil, generated end
    components[path] = resolve.module_name(path)
    parts[#parts + 1] = preload(resolve.module_name(path), generated, path)
  end

  local modules = {}
  for _, module in ipairs(app_modules(app)) do
    local source = util.read_file(module.path)
    if not source then return nil, module.path .. " vanished" end
    modules[module.path] = module.name
    parts[#parts + 1] = preload(module.name, source, module.path)
  end

  local manifest = {
    root = app.root,
    name = app.name,
    lang = app.lang,
    version = app.version,
    client = app.client,
    shell = app.shell,
    stylesheets = app.stylesheets,
    routes = route_manifest(app),
    components = components,
    modules = modules,
    rate_limit = options.rate_limit,
    security = options.security,
  }

  parts[#parts + 1] = string.format(
    "package.preload[%q] = function() return %s end",
    "lunar.app.manifest", bundle.literal(manifest))

  parts[#parts + 1] = table.concat({
    'local worker = require("lunar.site.worker")',
    'local app = worker.app(require("lunar.app.manifest"))',
    "-- The host calls this with a JSON request and gets a JSON response.",
    "function LUNAR_FETCH(payload)",
    "  return worker.handle(app, payload)",
    "end",
    "return LUNAR_FETCH",
  }, "\n")

  return table.concat(parts, "\n\n") .. "\n"
end

bundle.MODULES = MODULES
bundle.SERVER_MODULES = SERVER_MODULES
bundle.server_module_name = server_module_name
bundle.library_module_name = library_module_name
bundle.json = json

return bundle
