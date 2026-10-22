local errors = require("lunar.site.errors")
local fs = require("lunar.core.fs")
local html = require("lunar.core.html")
local ratelimit = require("lunar.http.ratelimit")
local render = require("lunar.site.render")
local response = require("lunar.http.response")
local routes_lib = require("lunar.site.routes")
local security_lib = require("lunar.http.security")
local manifest_lib = require("lunar.site.manifest")
local static_lib = require("lunar.http.static")
local util = require("lunar.core.util")
local watch_lib = require("lunar.site.watch")

local app = {}

local App = {}
App.__index = App

local function compiler_lib() return require("lunar.compiler") end

local function minify_setting(value, dev)
  if value ~= nil then return value and true or false end
  local flag = os.getenv("MINIFY")
  if flag == "0" or flag == "false" or flag == "no" then return false end
  if flag == "1" or flag == "true" or flag == "yes" then return true end
  return not dev
end
local function bundle_lib() return require("lunar.site.bundle") end

local function framework_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return (source:match("^(.*)/lunar/site/app%.lua$")) or "."
end

function app.new(options)
  options = options or {}
  local root = require("lunar.compiler.resolve").normalize(options.root or ".")
  if root == "." then root = "" end

  local declared, manifest_error = manifest_lib.read(root)
  if not declared then error(manifest_error, 0) end

  local function pick(key, fallback)
    if options[key] ~= nil then return options[key] end
    if declared[key] ~= nil then return declared[key] end
    return fallback
  end

  local self = setmetatable({
    root = root,
    dev = pick("dev", true) ~= false,
    name = pick("name", fs.basename(root ~= "" and root or "lunar")),
    lang = pick("lang", "en"),
    client = pick("client", true) ~= false,
    framework = options.framework or framework_root(),
    stylesheets = pick("stylesheets", {}),
    manifest = declared,
    modules = {},
  }, App)

  self.minify = minify_setting(pick("minify", nil), self.dev)

  package.path = table.concat({
    fs.join(root, "lib") .. "/?.lua",
    fs.join(root, "lib") .. "/?/init.lua",
    fs.join(root, "?.lua"),
    package.path,
  }, ";")

  self.cache = compiler_lib().cache({ root = root, watch = self.dev })
  self.cache:install()
  self.routes = routes_lib.discover(fs.join(root, "orbit"))

  self.version = tostring(pick("version", nil) or os.time())

  self.shell = util.read_file(fs.join(root, "app.html"))

  self.static = static_lib.new({
    root = fs.join(root, "static"),
    version = self.version,
    immutable_patterns = { "^fonts/", "^videos/" },
  })
  self.framework_static = static_lib.new({
    root = fs.join(self.framework, "static"),
    version = self.version,
  })

  self.security = security_lib.new(pick("security", {}))
  self.limiter = ratelimit.new(pick("rate_limit", {}))

  if self.dev and options.watch ~= false then
    self.watcher = watch_lib.new({ root = root, interval = options.watch_interval })
  end

  return self
end

function App:refresh(force)
  if not self.watcher then return false end
  if not self.watcher:changed({ force = force }) then return false end

  self.routes = routes_lib.discover(fs.join(self.root, "orbit"))
  self.shell = util.read_file(fs.join(self.root, "app.html"))
  self.modules = {}
  self.bundle_cache = nil
  return true
end

function App:generation()
  return self.watcher and self.watcher.generation or 0
end

function App:module(path)
  local frozen = self.frozen and self.frozen.modules[path]
  if frozen then
    local module = require(frozen)
    if type(module) ~= "table" then
      return nil, string.format("lunar: %s must return a table, got a %s", path, type(module))
    end
    return module
  end

  local source = util.read_file(path)
  if not source then return nil, "lunar: " .. path .. ": no such file" end

  local entry = self.modules[path]
  if entry and (not self.dev or entry.source == source) then return entry.module end

  local chunk, message = load(source, "@" .. path)
  if not chunk then return nil, "lunar: " .. tostring(message) end
  local ok, module = pcall(chunk)
  if not ok then return nil, "lunar: " .. path .. ": " .. tostring(module) end
  if type(module) ~= "table" then
    return nil, string.format("lunar: %s must return a table, got a %s", path, type(module))
  end

  self.modules[path] = { source = source, module = module }
  return module
end

function App:component(path)
  if self.frozen then
    local name = self.frozen.components[path]
    if not name then error("lunar: " .. path .. " is not in the bundle", 0) end
    return require(name)
  end
  local def, err = self.cache:get(path)
  if not def then error(err, 0) end
  return def
end


function App:render_page(req, route, params)
  local event = render.event(req, route, params)
  local levels = render.probe_chain(self, route, event)
  local drawn = render.drawn(levels)

  if #drawn == 0 then return nil end

  local defs, data = {}, {}
  for index, level in ipairs(drawn) do
    defs[index] = self:component(level.component)
    data[index] = level.data
  end

  if req:wants_json() then
    return response.json({ route = route.id, params = params, data = data }, 200,
      { ["Vary"] = "Accept", ["Cache-Control"] = "no-store" })
  end

  local body, ctx = render.chain(defs, data, { params = params })
  local document = render.document(self, {
    head = ctx.head,
    css = ctx.css,
    body = body,
    title = data[#data] and data[#data].title or nil,
    data = self.client and { route = route.id, params = params, data = data } or nil,
  })

  return response.html(document, 200, {
    ["Vary"] = "Accept",
    ["Cache-Control"] = self.dev and "no-store" or "no-cache",
  })
end

function App:render_error(req, status, message)
  local path = routes_lib.eclipse_for(self.routes, req.path)
  if path then
    local ok, document = pcall(function()
      local def = self:component(path)
      local body, ctx = render.chain({ def },
        { { status = status, message = message, title = tostring(status) } }, {})
      return render.document(self, {
        head = ctx.head, css = ctx.css, body = body, title = tostring(status),
        data = nil,
      })
    end)
    if ok then
      return response.html(document, status, { ["Cache-Control"] = "no-store" })
    end
    io.stderr:write("lunar: the error page itself failed: ", tostring(document), "\n")
  end

  return response.html(string.format(
    "<!doctype html><html lang=\"%s\"><head><meta charset=\"utf-8\">"
    .. "<title>%d</title></head><body><h1>%d %s</h1><p>%s</p></body></html>\n",
    html.escape(self.lang), status, status, response.status_text(status),
    html.escape(message or "")), status, { ["Cache-Control"] = "no-store" })
end

local function endpoint_handler(module, method)
  local handler = module[method]
  if handler == nil and method == "HEAD" then handler = module.GET end
  return handler
end

function App:run_endpoint(req, route, params)
  local module, err = self:module(route.endpoint)
  if not module then error(err, 0) end

  local handler = endpoint_handler(module, req.method)
  if not handler then
    local allowed = {}
    for name in pairs(module) do
      if name:match("^%u+$") then allowed[#allowed + 1] = name end
    end
    table.sort(allowed)
    return response.text("405 Method Not Allowed\n", 405,
      { ["Allow"] = table.concat(allowed, ", ") })
  end

  local value = handler(render.event(req, route, params))
  return response.coerce(value) or response.no_content()
end


function App:framework_response(req)
  local path = req.path

  if self.frozen then return nil end

  if path == "/_lunar/dev" then
    if not self.watcher then return nil end
    return response.json({ generation = self:generation(), version = self.version }, 200,
      { ["Cache-Control"] = "no-store" })
  end

  if path == "/_lunar/moonlight.lua" then
    local source, err = bundle_lib().build(self)
    if not source then
      return response.text("-- lunar: " .. tostring(err) .. "\n", 500,
        { ["Content-Type"] = "text/x-lua; charset=utf-8" })
    end
    return response.new(200, source, {
      ["Content-Type"] = "text/x-lua; charset=utf-8",
      ["Cache-Control"] = self.dev and "no-store" or "public, max-age=31536000, immutable",
    })
  end

  if path == "/_lunar/fengari.js" then
    local res = self.framework_static:serve(req, "/vendor/fengari-web.js")
    if res then
      res.headers["Cache-Control"] = "public, max-age=31536000, immutable"
      return res
    end
    return response.text("lunar: fengari-web.js is missing from the framework's static/vendor\n", 500)
  end

  return nil
end


function App:handle(req)
  if self.watcher then self:refresh() end

  local limited = self.limiter_middleware or self.limiter:middleware()
  self.limiter_middleware = limited
  local refused = limited(req)
  if refused then return refused end

  local framework = self:framework_response(req)
  if framework then return framework end

  local route, params = routes_lib.match(self.routes, req.path)

  local ok, result = pcall(function()
    if route and route.endpoint and not route.page then
      return self:run_endpoint(req, route, params)
    end
    if route and route.endpoint and route.page and req.method ~= "GET" and req.method ~= "HEAD" then
      return self:run_endpoint(req, route, params)
    end
    if route and route.page then
      if req.method ~= "GET" and req.method ~= "HEAD" then
        return response.text("405 Method Not Allowed\n", 405, { ["Allow"] = "GET, HEAD" })
      end
      return self:render_page(req, route, params)
    end
    return nil
  end)

  if not ok then
    if errors.is(result, "redirect") then
      return response.redirect(result.location, result.status)
    end
    if errors.is(result, "error") then
      return self:render_error(req, result.status, result.message)
    end
    io.stderr:write("lunar: ", tostring(result), "\n")
    return self:render_error(req, 500, self.dev and tostring(result) or nil)
  end

  if result then
    if req:is_head() then return response.strip_body(result) end
    return result
  end

  local file = self.static and self.static:serve(req, req.path)
  if file then
    if req:is_head() then return response.strip_body(file) end
    return file
  end

  if req.method ~= "GET" and req.method ~= "HEAD" then
    return response.text("405 Method Not Allowed\n", 405, { ["Allow"] = "GET, HEAD" })
  end
  return self:render_error(req, 404, "Not found")
end

function App:handler()
  return self.security:wrap(function(req) return self:handle(req) end)
end

function app.frozen(manifest)
  local self = setmetatable({
    root = manifest.root or "",
    dev = false,
    name = manifest.name or "lunar",
    lang = manifest.lang or "en",
    client = manifest.client ~= false,
    version = tostring(manifest.version or "0"),
    shell = manifest.shell,
    stylesheets = manifest.stylesheets or {},
    routes = manifest.routes or {},
    modules = {},
    frozen = {
      components = manifest.components or {},
      modules = manifest.modules or {},
    },
  }, App)

  self.security = security_lib.new(manifest.security or {})
  self.limiter = ratelimit.new(manifest.rate_limit or {})

  require("lunar.runtime.component").resolver =
    require("lunar.compiler.resolve").registry_resolver({
      root = self.root, components = self.frozen.components,
    })

  return self
end

app.App = App
app.framework_root = framework_root

return app
