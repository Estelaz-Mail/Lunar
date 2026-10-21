--- An app: a directory with an `orbit/` in it, served.
--
-- This is the half that turns a directory into a website. It discovers the
-- orbit, compiles what a request needs, runs the probes, renders the page
-- inside its shells, and wraps the result in the document. Nothing is built
-- ahead of time: in development the compiler cache notices a changed file and
-- recompiles it, and in production it compiles each component once.

local errors = require("lunar.site.errors")
local fs = require("lunar.core.fs")
local html = require("lunar.core.html")
local ratelimit = require("lunar.http.ratelimit")
local render = require("lunar.site.render")
local response = require("lunar.http.response")
local routes_lib = require("lunar.site.routes")
local security_lib = require("lunar.http.security")
local static_lib = require("lunar.http.static")
local util = require("lunar.core.util")

local app = {}

local App = {}
App.__index = App

-- The compiler and the bundler are required where they are used, not here.
-- An app built by `app.frozen` — one running on a platform with no filesystem
-- — never compiles anything, and making these lazy is what keeps the compiler
-- out of the bundle it ships in.
local function compiler_lib() return require("lunar.compiler") end
local function bundle_lib() return require("lunar.site.bundle") end

--- Where the framework itself lives, for the files it serves of its own
-- (Fengari, the moonlight bundle). Derived from this file's path, because a
-- framework that has to be told where it is installed is a framework with a
-- configuration step.
local function framework_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return (source:match("^(.*)/lunar/site/app%.lua$")) or "."
end

--- `options` is `{ root, dev, version, name, lang, client, security, rate_limit,
-- stylesheets }`.
function app.new(options)
  options = options or {}
  local root = (options.root or "."):gsub("/+$", "")

  local self = setmetatable({
    root = root,
    dev = options.dev ~= false,
    name = options.name or fs.basename(root ~= "" and root or "lunar"),
    lang = options.lang or "en",
    client = options.client ~= false,
    framework = options.framework or framework_root(),
    stylesheets = options.stylesheets or {},
    modules = {},
  }, App)

  -- An app's own Lua — the `lib/` a probe requires — is found the
  -- ordinary way, by `package.path`. The app's root is prepended rather than
  -- appended, so a module of the app's shadows one of the framework's and not
  -- the other way round.
  package.path = table.concat({
    fs.join(root, "lib") .. "/?.lua",
    fs.join(root, "lib") .. "/?/init.lua",
    fs.join(root, "?.lua"),
    package.path,
  }, ";")

  self.cache = compiler_lib().cache({ root = root, watch = self.dev })
  self.cache:install()
  self.routes = routes_lib.discover(fs.join(root, "orbit"))

  -- The version goes in every asset URL and in the ETag of every file, so one
  -- deploy cannot serve another's bytes from a cache. In development it is the
  -- boot time, which is as good as a build id and needs no build.
  self.version = tostring(options.version or os.time())

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

  self.security = security_lib.new(options.security or {})
  self.limiter = ratelimit.new(options.rate_limit or {})

  return self
end

--- A `.lua` file in a route directory: a probe or an endpoint.
--
-- Loaded with the same watch rule as a component, so editing a probe in
-- development takes effect on the next request and nothing is cached twice.
function App:module(path)
  -- A frozen app — one built for a platform with no filesystem — carries its
  -- modules in the bundle instead of on disk.
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

-- Rendering --------------------------------------------------------------------

--- Renders a page route. Returns a response.
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

  -- The client router asks for the same URL with `Accept: application/json`
  -- and gets the data it needs to render the route itself.
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

--- Renders the eclipse, or a plain body when the app has none.
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

-- The framework's own URLs --------------------------------------------------------

function App:framework_response(req)
  local path = req.path

  -- A frozen app does not serve these: the moonlight bundle and Fengari were
  -- published as static files when it was built, and the platform serves them.
  if self.frozen then return nil end

  if path == "/_lunar/moonlight.lua" then
    local source, err = bundle_lib().build(self)
    if not source then
      return response.text("-- lunar: " .. tostring(err) .. "\n", 500,
        { ["Content-Type"] = "text/x-lua; charset=utf-8" })
    end
    return response.new(200, source, {
      ["Content-Type"] = "text/x-lua; charset=utf-8",
      -- The bundle is assembled from source and changes with the app, so it
      -- is versioned in its URL and immutable at that version.
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

-- Dispatch ------------------------------------------------------------------------

--- Serves one request. This is the whole decision tree, in order.
function App:handle(req)
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
      -- A directory with both answers pages on GET and the endpoint on
      -- anything else, which is what a page with a form wants.
      return self:run_endpoint(req, route, params)
    end
    if route and route.page then
      if req.method ~= "GET" and req.method ~= "HEAD" then
        -- A page with no `api.lua` next to it answers GET and nothing
        -- else. Rendering it for a POST would turn a stray form into a page
        -- that looks like it worked.
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

  -- Not a route: the app's own files, then the error page. The order is what
  -- lets a page route sit in front of the static files. A frozen app has no
  -- files of its own — the platform served them before the request got here.
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

--- The handler to hand to `http.server`, with the security headers wrapped
-- around everything it produces.
function App:handler()
  return self.security:wrap(function(req) return self:handle(req) end)
end

--- An app with no filesystem under it.
--
-- Everything `app.new` would read at boot — the route tree, the components,
-- the probes, the document shell — is in the manifest the bundle
-- carries, because the platform this is for has no directory to walk and no
-- file to open. Serving a request is otherwise exactly the same code.
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

  -- `import()` inside a component looks in the bundle, by the same path
  -- arithmetic the compiler used when it was on a disk.
  require("lunar.runtime.component").resolver =
    require("lunar.compiler.resolve").registry_resolver({
      root = self.root, components = self.frozen.components,
    })

  return self
end

app.App = App
app.framework_root = framework_root

return app
