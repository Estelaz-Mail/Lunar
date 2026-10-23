local fs = require("lunar.core.fs")
local minify = require("lunar.core.minify")
local json = require("lunar.core.json")
local resolve = require("lunar.compiler.resolve")
local util = require("lunar.core.util")

local bundle = {}

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
  "lunar/runtime/wasm.lua",
  "lunar/site/moonlight.lua",
  "lunar/site/boot.lua",
}

local function module_name(path)
  return (path:gsub("%.lua$", ""):gsub("/", "."):gsub("%.init$", ""))
end

local function framework_source(app, path)
  local source = util.read_file(path)
  if not source then return nil end
  if app.minify then return minify.lua_source(source) end
  return source
end

local function preload(name, source, chunk_name)
  local level = ""
  while source:find("]" .. level .. "]", 1, true) do level = level .. "=" end
  return string.format(
    "package.preload[%q] = assert(load([%s[\n%s]%s], %q))",
    name, level, source, level, "@" .. chunk_name)
end

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

function bundle.build(app)
  if app.bundle_cache and not app.dev then
    return app.bundle_cache
  end

  local parts = {}
  local inventory = {}
  local function keep(kind, name, piece)
    parts[#parts + 1] = piece
    inventory[#inventory + 1] = { kind = kind, name = name, bytes = #piece,
      piece = bundle.detailed and piece or nil }
  end

  for _, relative in ipairs(MODULES) do
    local path = fs.join(app.framework, relative)
    local source = framework_source(app, path)
    if not source then return nil, path .. " is missing from the framework" end
    keep("framework", module_name(relative), preload(module_name(relative), source, relative))
  end

  local components = {}
  for _, path in ipairs(app_components(app)) do
    local def, generated = app.cache:get(path)
    if not def then return nil, generated end
    components[path] = resolve.module_name(path)
    keep("component", path, preload(resolve.module_name(path), generated, path))
  end

  local registry = {
    root = app.root,
    components = components,
    routes = route_map(app),
  }

  keep("registry", "lunar.app.registry", string.format(
    "package.preload[%q] = function() return %s end",
    "lunar.app.registry", bundle.literal(registry)))

  if app.dev then
    local path = fs.join(app.framework, "lunar/site/reload.lua")
    local source = framework_source(app, path)
    if source then
      keep("framework", "lunar.site.reload",
        preload("lunar.site.reload", source, "lunar/site/reload.lua"))
    end
  end

  local tail = {
    'local registry = require("lunar.app.registry")',
    'local started, failure = pcall(function()',
    '  require("lunar.site.boot").start(registry)',
    'end)',
    'if not started then print("lunar: the client half did not start: "'
      .. ' .. tostring(failure)) end',
  }
  if app.dev then
    tail[#tail + 1] = 'pcall(function() require("lunar.site.reload").watch() end)'
  end
  tail[#tail + 1] = 'return registry'
  keep("boot", "the start-up tail", table.concat(tail, "\n"))

  local source = table.concat(parts, "\n\n") .. "\n"
  app.bundle_cache = source
  app.bundle_inventory = inventory
  return source
end

function bundle.inventory(app)
  bundle.detailed = true
  app.bundle_cache = nil
  local source, err = bundle.build(app)
  bundle.detailed = false
  if not source then return nil, err end

  local inventory = app.bundle_inventory
  app.bundle_cache, app.bundle_inventory = nil, nil
  return inventory, source
end

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

local SERVER_MODULES = {
  "lunar/init.lua",
  "lunar/core/util.lua",
  "lunar/core/html.lua",
  "lunar/core/json.lua",
  "lunar/core/url.lua",
  "lunar/core/mime.lua",
  "lunar/core/fs.lua",
  "lunar/core/base64.lua",
  "lunar/core/gzip.lua",
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
  "lunar/http/compress.lua",
  "lunar/http/static.lua",
  "lunar/http/security.lua",
  "lunar/http/ratelimit.lua",
  "lunar/site/errors.lua",
  "lunar/site/manifest.lua",
  "lunar/site/wasm.lua",
  "lunar/wasm/encode.lua",
  "lunar/wasm/module.lua",
  "lunar/wasm/parse.lua",
  "lunar/wasm/compile.lua",
  "lunar/wasm/runtime.lua",
  "lunar/wasm/parts.lua",
  "lunar/site/watch.lua",
  "lunar/site/prerender.lua",
  "lunar/site/routes.lua",
  "lunar/site/render.lua",
  "lunar/site/app.lua",
  "lunar/site/worker.lua",
}

local function server_module_name(path)
  return "lunar.app.module:" .. path
end

local function library_module_name(root, path)
  local relative = path
  local prefix = (root ~= "" and root or ".") .. "/lib/"
  if relative:sub(1, #prefix) == prefix then relative = relative:sub(#prefix + 1) end
  return (relative:gsub("%.lua$", ""):gsub("/", "."))
end

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

function bundle.server(app, options)
  options = options or {}
  local parts = {}

  for _, relative in ipairs(SERVER_MODULES) do
    local path = fs.join(app.framework, relative)
    local source = framework_source(app, path)
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
    integrity = app:client_integrity(),
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
