local fs = require("lunar.core.fs")
local minify = require("lunar.core.minify")
local json = require("lunar.core.json")
local resolve = require("lunar.compiler.resolve")
local util = require("lunar.core.util")
local sha256 = require("lunar.crypto.sha256")

local bundle = {}

bundle.CHUNKS = "/_lunar/chunk/"

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
  "lunar/site/chunks.lua",
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


local function imports_of(source)
  local tokens, position = {}, 1
  while position <= #source do
    local char = source:sub(position, position)
    local comment = source:sub(position, position + 1) == "--"
    local first = comment and position + 2 or position
    local level = source:match("^%[(=*)%[", first)
    if comment or level then
      if level then
        local closing = "]" .. level .. "]"
        local stop = source:find(closing, first + #level + 2, true)
        if not stop then return {}, false end
        local finish = stop + #closing
        if not comment then
          tokens[#tokens + 1] = { kind = "string", literal = source:sub(first, finish - 1) }
        end
        position = finish
      else
        position = source:find("\n", first, true) or (#source + 1)
      end
    elseif char == '"' or char == "'" then
      local stop = position + 1
      while stop <= #source do
        local next_char = source:sub(stop, stop)
        if next_char == "\\" then stop = stop + 2
        elseif next_char == char then break
        else stop = stop + 1 end
      end
      tokens[#tokens + 1] = { kind = "string", literal = source:sub(position, stop) }
      position = stop + 1
    elseif char:match("[%a_]") then
      local name = source:match("^[%w_]+", position)
      tokens[#tokens + 1] = { kind = "name", value = name }
      position = position + #name
    else
      if not char:match("%s") then tokens[#tokens + 1] = { kind = char } end
      position = position + 1
    end
  end

  local literals = {}
  for index, token in ipairs(tokens) do
    if token.kind == "name" and token.value == "import" then
      local argument = tokens[index + 1]
      if argument and argument.kind == "(" then
        argument = tokens[index + 2]
        local closing = tokens[index + 3]
        if not closing or closing.kind ~= ")" then return {}, false end
      end
      if not argument or argument.kind ~= "string" then return {}, false end
      local literal = load("return " .. argument.literal, "=import", "t", {})
      if not literal then return {}, false end
      local ok, request = pcall(literal)
      if not ok or type(request) ~= "string" then return {}, false end
      literals[#literals + 1] = request
    end
  end
  return literals, true
end

local function reachable(app, roots, known)
  local seen, order = {}, {}
  local queue = {}
  for _, path in ipairs(roots) do queue[#queue + 1] = path end

  while #queue > 0 do
    local path = table.remove(queue)
    if not seen[path] then
      seen[path] = true
      order[#order + 1] = path
      local _, generated = app.cache:get(path)
      if type(generated) ~= "string" then return nil, path .. " does not compile" end
      local literals, certain = imports_of(generated)
      if not certain then return nil, path .. " imports something that is not a literal" end
      for _, request in ipairs(literals) do
        local target = resolve.path(request, path, app.root)
        if known[target] == nil then target = resolve.normalize(target) end
        if known[target] == nil then return nil, path .. " imports " .. request end
        queue[#queue + 1] = target
      end
    end
  end
  return order
end

function bundle.plan(app)
  if app.split_plan ~= nil then return app.split_plan end

  local known = {}
  for _, path in ipairs(app_components(app)) do known[path] = true end

  local routes = route_map(app)
  local per_route, counted = {}, {}
  local refused = nil

  for id, paths in pairs(routes) do
    local order, err = reachable(app, paths, known)
    if not order then
      refused = err
      break
    end
    per_route[id] = order
    for _, path in ipairs(order) do counted[path] = (counted[path] or 0) + 1 end
  end

  local plan
  if refused then
    plan = { split = false, reason = refused }
  else
    local core, chunks = {}, {}
    for path in pairs(known) do
      if (counted[path] or 0) ~= 1 then core[#core + 1] = path end
    end
    table.sort(core)

    for id, order in pairs(per_route) do
      local own = {}
      for _, path in ipairs(order) do
        if counted[path] == 1 then own[#own + 1] = path end
      end
      table.sort(own)
      if #own > 0 then chunks[id] = own end
    end
    plan = { split = true, core = core, chunks = chunks }
  end

  app.split_plan = plan
  return plan
end

local function component_part(app, path)
  local def, generated = app.cache:get(path)
  if not def then return nil, generated end
  return preload(resolve.module_name(path), generated, path)
end

function bundle.chunks(app)
  if not app.split then return {} end
  if app.chunk_cache and not app.dev then return app.chunk_cache end

  local plan = bundle.plan(app)
  if not plan.split then
    app.chunk_cache = {}
    return app.chunk_cache
  end

  local out = {}
  for id, paths in pairs(plan.chunks) do
    local pieces = {}
    for _, path in ipairs(paths) do
      local piece, err = component_part(app, path)
      if not piece then return nil, err end
      pieces[#pieces + 1] = piece
    end
    local source = table.concat(pieces, "\n\n") .. "\n"
    out[id] = { name = sha256.hex(sha256.digest(source)) .. ".lua", source = source, paths = paths }
  end

  app.chunk_cache = out
  return out
end

function bundle.chunk(app, name)
  local chunks = bundle.chunks(app)
  if not chunks then return nil end
  for _, chunk in pairs(chunks) do
    if chunk.name == name then return chunk.source end
  end
  return nil
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

  local plan = app.split and bundle.plan(app) or { split = false }
  local chunks = plan.split and bundle.chunks(app) or {}
  if plan.split and not chunks then return nil, "a chunk did not compile" end

  local held = nil
  if plan.split then
    held = {}
    for _, path in ipairs(plan.core) do held[path] = true end
  end

  local components = {}
  for _, path in ipairs(app_components(app)) do
    local def, generated = app.cache:get(path)
    if not def then return nil, generated end
    components[path] = resolve.module_name(path)
    if not held or held[path] then
      keep("component", path, preload(resolve.module_name(path), generated, path))
    end
  end

  local routed = {}
  for id, chunk in pairs(chunks) do routed[id] = bundle.CHUNKS .. chunk.name end

  local registry = {
    root = app.root,
    components = components,
    routes = route_map(app),
    chunks = next(routed) ~= nil and routed or nil,
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
  "lunar/core/terminal.lua",
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

  local chunk_urls = {}
  for id, chunk in pairs(bundle.chunks(app) or {}) do
    chunk_urls[id] = bundle.CHUNKS .. chunk.name
  end

  local manifest = {
    chunks = next(chunk_urls) ~= nil and chunk_urls or nil,
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
