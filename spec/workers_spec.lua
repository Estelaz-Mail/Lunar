local bundle = require("lunar.site.bundle")
local json = require("lunar.core.json")
local lunar = require("lunar")
local request = require("lunar.http.request")
local workers = require("lunar.site.targets.workers")

local T = {}

local APP = "examples/tranquility"

local function app(root)
  return lunar.app({ root = root or APP, dev = false, version = "spec" })
end

local function frozen_fetch(root)
  local source, err = bundle.server(app(root))
  assert(source, err)

  local saved_preload, saved_loaded = {}, {}
  for name, value in pairs(package.preload) do saved_preload[name] = value end
  for name, value in pairs(package.loaded) do saved_loaded[name] = value end

  local path, cpath = package.path, package.cpath
  package.path, package.cpath = "", ""
  for name in pairs(package.loaded) do
    if name == "lunar" or name:find("^lunar%.") then package.loaded[name] = nil end
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

    assert(serve(fetch, "GET", "/blog/nope").status == 404)
    assert(serve(fetch, "GET", "/nothing").status == 404)

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


function T.turns_a_name_into_one_a_worker_can_have()
  assert(workers.worker_name("tranquility") == "tranquility")
  assert(workers.worker_name("My App!") == "my-app")
  assert(workers.worker_name("--weird--") == "weird")
  assert(workers.worker_name("") == "lunar-app")
end

function T.writes_a_wrangler_config_that_parses_and_says_what_it_must()
  local config = workers.wrangler_config(app(), { compatibility_date = "2026-10-21" })
  local without_comments = config:gsub("\n%s*//[^\n]*", "")
  local parsed = assert(json.decode(without_comments))

  assert(parsed.main == "src/worker.ts")
  assert(parsed.compatibility_date == "2026-10-21")
  assert(parsed.assets.directory == "./public/")
  assert(parsed.assets.binding == "ASSETS")
  assert(parsed.rules[1].type == "Text")
  assert(parsed.rules[1].globs[1] == "**/*.lua")
  assert(parsed.rules[2].type == "CompiledWasm")
  assert(parsed.alias == nil)
end

function T.generates_every_file_the_deploy_needs()
  local out = os.tmpname()
  os.remove(out)
  local result, err = workers.generate(app(), { out = out })
  assert(result, err)

  local written = {}
  for _, file in ipairs(result.files) do written[file.path] = true end
  for _, wanted in ipairs({ "src/app.lua", "src/worker.ts", "src/bridge.ts",
    "src/lua54.wasm", "wrangler.jsonc", "package.json",
    "public/_lunar/moonlight.lua", "public/_lunar/runtime/boot",
    "public/_lunar/runtime/bridge", "public/_lunar/runtime/lua54.wasm" }) do
    assert(written[wanted], wanted .. " was not written")
  end

  local util = require("lunar.core.util")
  local app_lua = assert(util.read_file(out .. "/src/app.lua"))
  local headers = assert(util.read_file(out .. "/public/_headers"))
  assert(headers:find("/_lunar/runtime/boot", 1, true))
  assert(headers:find("Content-Type: text/javascript; charset=utf-8", 1, true))
  assert(load(app_lua, "@app.lua"), "the bundle is not valid Lua")
  assert(not app_lua:find('package.preload%["lunar%.compiler%.parser"%]'))
  assert(not app_lua:find('package.preload%["lunar%.http%.server"%]'),
    "the socket server has no business on an edge runtime")

  os.execute("rm -rf " .. out)
end

local function outside_the_working_directory()
  local root = string.format("%s/lunar-frozen-%d-%d", os.getenv("TMPDIR") or "/tmp",
    os.time(), math.random(100000))
  local fs = require("lunar.core.fs")
  local util = require("lunar.core.util")

  fs.mkdirp(fs.join(root, "orbit"))
  fs.mkdirp(fs.join(root, "lib"))
  assert(util.write_file(fs.join(root, "orbit/page.lunar"), [[
<script>
  props { data = {} }
  local Card = import("./Card.lunar")
  local Nav = import("/lib/Nav.lunar")
</script>
<h1>frozen</h1>
<Card title="a sibling" />
<Nav label="a library" />
]]))
  assert(util.write_file(fs.join(root, "orbit/Card.lunar"), [[
<script>
  props { title = "untitled" }
</script>
<section class="card">{title}</section>
]]))
  assert(util.write_file(fs.join(root, "lib/Nav.lunar"), [[
<script>
  props { label = "nav" }
</script>
<nav>{label}</nav>
]]))

  local cwd = os.getenv("PWD") or "."
  local depth = 0
  for _ in cwd:gmatch("[^/]+") do depth = depth + 1 end
  local spelled = ("../"):rep(depth) .. root:gsub("^/", "")
  return root, spelled
end

function T.an_app_outside_the_working_directory_keeps_its_imports()
  local root, spelled = outside_the_working_directory()

  local fetch, restore = frozen_fetch(spelled)
  local ok, err = pcall(function()
    local home = serve(fetch, "GET", "/")
    assert(home.status == 200, "the page answered " .. home.status
      .. ": " .. tostring(home.body):sub(1, 200))
    assert(home.body:find("a sibling", 1, true),
      "the sibling import rendered, which a collapsed ../ breaks")
    assert(home.body:find("a library", 1, true), "and so did the one from lib/")
  end)
  restore()
  os.execute("rm -rf " .. root)
  assert(ok, err)
end

function T.an_app_reached_through_its_parent_freezes_the_same_way()
  local sideways = "examples/../examples/tranquility"

  local plain = app()
  local reached = app(sideways)
  assert(#plain.routes == #reached.routes, "the same routes were found")

  local fetch, restore = frozen_fetch(sideways)
  local ok, err = pcall(function()
    local home = serve(fetch, "GET", "/")
    assert(home.status == 200, "the home page answered " .. home.status
      .. ": " .. tostring(home.body):sub(1, 200))
    assert(home.body:find("A framework in Lua", 1, true), "the page rendered")
    assert(home.body:find('class="counter', 1, true),
      "and so did the component it imports, which is what a collapsed path breaks")

    local post = serve(fetch, "GET", "/blog/why-lua")
    assert(post.status == 200, post.status)
    assert(post.body:find("Why Lua", 1, true))
  end)
  restore()
  assert(ok, err)
end

return T
