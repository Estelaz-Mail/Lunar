--- The Cloudflare Workers target.
--
-- The thing worth testing without the edge is that the frozen app is really
-- frozen: it must answer a request with no filesystem under it, because that
-- is the one thing an edge runtime cannot provide. So the bundle is loaded in
-- a state whose `io` and `package.path` have been taken away, and then asked
-- to serve the same pages the ordinary server serves.

local bundle = require("lunar.site.bundle")
local json = require("lunar.core.json")
local lunar = require("lunar")
local request = require("lunar.http.request")
local workers = require("lunar.site.targets.workers")

local T = {}

local APP = "examples/tranquility"

local function app()
  return lunar.app({ root = APP, dev = false, version = "spec" })
end

--- Loads the server bundle the way the Worker does — one chunk, one call —
-- and returns its fetch function.
--
-- The chunk gets an environment with no `io`, no `os.execute`, no `require`
-- for anything outside the bundle and no `package.path`, so anything that
-- reaches for a file fails here rather than in production.
local function frozen_fetch()
  local source, err = bundle.server(app())
  assert(source, err)

  local saved_preload, saved_loaded = {}, {}
  for name, value in pairs(package.preload) do saved_preload[name] = value end
  for name, value in pairs(package.loaded) do saved_loaded[name] = value end

  local path, cpath = package.path, package.cpath
  package.path, package.cpath = "", ""
  for _, relative in ipairs(bundle.SERVER_MODULES) do
    package.loaded[(relative:gsub("%.lua$", ""):gsub("/", "."):gsub("%.init$", ""))] = nil
  end

  local chunk, message = load(source, "@app.lua")
  assert(chunk, message)
  local ok, fetch = pcall(chunk)

  package.path, package.cpath = path, cpath

  local function restore()
    for name in pairs(package.preload) do
      if saved_preload[name] == nil then package.preload[name] = nil end
    end
    for name in pairs(package.loaded) do
      if saved_loaded[name] == nil then package.loaded[name] = nil end
    end
    for name, value in pairs(saved_loaded) do package.loaded[name] = value end
  end

  if not ok then
    restore()
    error("the bundle did not start: " .. tostring(fetch), 2)
  end
  return fetch, restore
end

local function serve(fetch, method, path, extra)
  local payload = {
    method = method or "GET",
    url = "https://demo.workers.dev" .. (path or "/"),
    headers = { accept = "text/html" },
    ip = "203.0.113.4",
  }
  for key, value in pairs(extra or {}) do payload[key] = value end
  return assert(json.decode(fetch(json.encode(payload))))
end

--- The test this target exists to pass.
function T.serves_the_whole_app_with_no_filesystem_under_it()
  local fetch, restore = frozen_fetch()
  local ok, err = pcall(function()
    local home = serve(fetch, "GET", "/")
    assert(home.status == 200, home.status)
    assert(home.body:find("A framework in Lua", 1, true), "the page rendered")
    assert(home.body:find("class=\"counter", 1, true), "an imported component rendered")
    assert(home.headers["Content-Security-Policy"], "the headers came with it")

    local post = serve(fetch, "GET", "/blog/why-lua")
    assert(post.status == 200)
    assert(post.body:find("Why Lua, for both halves", 1, true))

    -- A load that fails the request, and a path that is no route at all.
    assert(serve(fetch, "GET", "/blog/nope").status == 404)
    assert(serve(fetch, "GET", "/nothing").status == 404)

    -- An endpoint, and a form body that arrived as a string.
    local endpoint = serve(fetch, "GET", "/api/time")
    assert(endpoint.status == 200)
    assert(json.decode(endpoint.body).route == "/api/time")

    local form = serve(fetch, "POST", "/api/time", {
      headers = { ["content-type"] = "application/x-www-form-urlencoded" },
      body = "echo=hello",
    })
    assert(json.decode(form.body).echoed == "hello")
  end)
  restore()
  assert(ok, err)
end

--- The frozen app serves no files: the platform did that before the request
-- reached the Worker, and a Worker that tried would need a disk.
function T.leaves_the_files_to_the_platform()
  local fetch, restore = frozen_fetch()
  local ok, err = pcall(function()
    local css = serve(fetch, "GET", "/css/app.css")
    assert(css.status == 404, "a static path is not the app's to answer")
    assert(serve(fetch, "GET", "/_lunar/moonlight.lua").status == 404)
  end)
  restore()
  assert(ok, err)
end

--- The page the Worker renders is the page the ordinary server renders.
function T.renders_what_the_server_renders()
  local fetch, restore = frozen_fetch()
  local ok, err = pcall(function()
    local instance = app()
    for _, path in ipairs({ "/", "/about", "/blog" }) do
      local direct = instance:handler()(request.new({
        method = "GET", target = path, headers = { host = "demo.workers.dev" },
      }, {}))
      local edge = serve(fetch, "GET", path)
      assert(edge.status == direct.status, path)
      assert(edge.body == direct.body, path .. " differs between the two")
    end
  end)
  restore()
  assert(ok, err)
end

-- What is generated ---------------------------------------------------------------

function T.turns_a_name_into_one_a_worker_can_have()
  assert(workers.worker_name("tranquility") == "tranquility")
  assert(workers.worker_name("My App!") == "my-app")
  assert(workers.worker_name("--weird--") == "weird")
  assert(workers.worker_name("") == "lunar-app")
end

function T.writes_a_wrangler_config_that_parses_and_says_what_it_must()
  local config = workers.wrangler_config(app(), { compatibility_date = "2026-10-21" })
  -- JSONC: the comments are the point, so they are stripped before parsing.
  local without_comments = config:gsub("\n%s*//[^\n]*", "")
  local parsed = assert(json.decode(without_comments))

  assert(parsed.main == "src/worker.mjs")
  assert(parsed.compatibility_date == "2026-10-21")
  assert(parsed.assets.directory == "./public/")
  assert(parsed.assets.binding == "ASSETS")
  -- Without this rule the bundler reads app.lua as JavaScript.
  assert(parsed.rules[1].type == "Text")
  assert(parsed.rules[1].globs[1] == "**/*.lua")
  -- Fengari binds Node's `fs` and `tmp` as it loads, on a runtime that has
  -- neither; both are aliased rather than polyfilled.
  assert(parsed.alias.fs:find("fs%-stub"))
  assert(parsed.alias.tmp:find("tmp%-stub"))
  assert(parsed.alias["readline-sync"]:find("absent"))
end

function T.generates_every_file_the_deploy_needs()
  local out = os.tmpname()
  os.remove(out)
  local result, err = workers.generate(app(), { out = out })
  assert(result, err)

  local written = {}
  for _, file in ipairs(result.files) do written[file.path] = true end
  for _, wanted in ipairs({ "src/app.lua", "src/worker.mjs", "src/fs-stub.cjs",
    "src/tmp-stub.cjs", "src/absent.cjs", "wrangler.jsonc", "package.json",
    "public/_lunar/moonlight.lua", "public/_lunar/fengari.js" }) do
    assert(written[wanted], wanted .. " was not written")
  end

  local util = require("lunar.core.util")
  local app_lua = assert(util.read_file(out .. "/src/app.lua"))
  assert(load(app_lua, "@app.lua"), "the bundle is not valid Lua")
  -- The compiler is not in it: a frozen app has nothing left to compile, and
  -- leaving it out is most of the difference in size.
  assert(not app_lua:find('package.preload%["lunar%.compiler%.parser"%]'))
  assert(not app_lua:find('package.preload%["lunar%.http%.server"%]'),
    "the socket server has no business on an edge runtime")

  os.execute("rm -rf " .. out)
end

return T
