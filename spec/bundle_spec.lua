--- The moonlight bundle: that it carries everything the browser needs, and
--- that what it mounts is what the server sent.
--
-- The bundle is loaded in this Lua state — `package.preload` is saved and put
-- back afterwards — and then driven against the mock DOM with the very
-- payload the server serialised into the document. If the two agree, the
-- browser half of a real page agrees too: nothing in between is mocked except
-- the DOM itself.

local bundle = require("lunar.site.bundle")
local json = require("lunar.core.json")
local lunar = require("lunar")
local mock = require("mockdom")
local request = require("lunar.http.request")

local T = {}

local APP = "examples/tranquility"

local function app()
  return lunar.app({ root = APP, dev = true, version = "spec" })
end

local function get(instance, path, headers)
  local all = headers or {}
  all.host = "localhost"
  local req = request.new({ method = "GET", target = path, headers = all }, {})
  req.ip = "203.0.113.7"
  return instance:handler()(req)
end

--- Loads the bundle, keeping this state's modules out of its way and putting
-- them back afterwards, and returns its registry.
local function with_bundle(fn)
  local source, err = bundle.build(app())
  assert(source, err)

  local saved_preload, saved_loaded = {}, {}
  for name, value in pairs(package.preload) do saved_preload[name] = value end
  for name, value in pairs(package.loaded) do saved_loaded[name] = value end

  local chunk, message = load(source, "@moonlight.lua")
  assert(chunk, message)

  -- The runtime modules in the bundle must be the ones the bundle carries,
  -- not the ones this process already loaded from disk.
  for _, relative in ipairs(bundle.MODULES) do
    package.loaded[(relative:gsub("%.lua$", ""):gsub("/", "."))] = nil
  end

  local ok, registry = pcall(chunk)

  local result
  if ok then result = table.pack(pcall(fn, registry, source)) end

  for name in pairs(package.preload) do
    if saved_preload[name] == nil then package.preload[name] = nil end
  end
  for name in pairs(package.loaded) do
    if saved_loaded[name] == nil then package.loaded[name] = nil end
  end
  for name, value in pairs(saved_loaded) do package.loaded[name] = value end

  assert(ok, "the bundle did not load: " .. tostring(registry))
  assert(result[1], result[2])
  return table.unpack(result, 2, result.n)
end

function T.carries_every_module_the_browser_half_needs()
  local names = with_bundle(function(registry, source)
    local found = {}
    for name in source:gmatch('package%.preload%[("[^"]+")%]') do
      found[#found + 1] = name:sub(2, -2)
    end
    assert(registry.routes["/"], "the home route is in the registry")
    assert(registry.components[APP .. "/orbit/page.lunar"])
    assert(registry.components[APP .. "/lib/Counter.lunar"],
      "a component only reached through import() is in the bundle too")
    return found
  end)

  local wanted = { "lunar.runtime.component", "lunar.runtime.signal", "lunar.runtime.dom",
    "lunar.runtime.scope", "lunar.core.html", "lunar.core.json", "lunar.site.moonlight",
    "lunar.site.boot", "lunar.app.registry" }
  for _, name in ipairs(wanted) do
    local present = false
    for _, candidate in ipairs(names) do
      if candidate == name then present = true end
    end
    assert(present, name .. " is missing from the bundle")
  end
end

--- The test this whole arrangement exists for.
function T.mounts_what_the_server_rendered()
  local instance = app()

  for _, path in ipairs({ "/", "/about", "/blog", "/blog/why-lua" }) do
    local document = get(instance, path).body
    local payload = json.decode(document:match('id="lunar%-data">(.-)</script>'))
    assert(payload, "the page carries its data")
    local server = document:match('<div id="lunar">(.*)</div>%s*<script type="application/json"')
    assert(server, "the page carries its markup")

    local browser = with_bundle(function(registry)
      local moonlight = require("lunar.site.moonlight")
      local dom = mock.new()
      moonlight.start(registry, payload, dom, dom.body)
      return mock.serialize(dom.body)
    end)

    assert(browser == server, string.format(
      "%s differs\n  server:  %s\n  browser: %s", path, server:sub(1, 400), browser:sub(1, 400)))
  end
end

function T.takes_over_and_then_updates()
  local instance = app()
  local document = get(instance, "/").body
  local payload = json.decode(document:match('id="lunar%-data">(.-)</script>'))

  local markup = with_bundle(function(registry)
    local moonlight = require("lunar.site.moonlight")
    local dom = mock.new()
    local session = moonlight.start(registry, payload, dom, dom.body)

    -- The counter's `+`, found the way a visitor would: by its class.
    local function find(tag, class)
      local found
      local function walk(node)
        if node.kind == "element" and node.tag == tag
          and (node.attributes.class or ""):find(class, 1, true) then
          found = found or node
        end
        for _, child in ipairs(node.children) do walk(child) end
      end
      walk(dom.body)
      return found
    end

    for _ = 1, 10 do mock.fire(find("button", "up"), "click") end
    mock.input(find("input", "name"), "Ada")
    assert(session.route == "/")
    return mock.serialize(dom.body)
  end)

  assert(markup:find(">10<", 1, true), "the counter counted")
  assert(markup:find("even", 1, true), "the derived value followed")
  assert(markup:find("Ten already", 1, true), "the {#if} block appeared")
  assert(markup:find("Hello, Ada.", 1, true), "the binding reached the derived greeting")
end

--- A client-side navigation is a swap of the chain, so the previous route's
-- effects have to stop: if they did not, they would keep patching nodes that
-- are no longer in the document.
function T.navigating_replaces_the_page_and_stops_the_old_one()
  local instance = app()
  local home = json.decode(get(instance, "/").body:match('id="lunar%-data">(.-)</script>'))
  local blog = json.decode(get(instance, "/blog").body:match('id="lunar%-data">(.-)</script>'))

  with_bundle(function(registry)
    local moonlight = require("lunar.site.moonlight")
    local dom = mock.new()
    local session = moonlight.start(registry, home, dom, dom.body)
    local first = session.instances[#session.instances]

    assert(mock.serialize(dom.body):find("A framework in Lua", 1, true))
    assert(session:swap(blog))
    local markup = mock.serialize(dom.body)
    assert(markup:find("Why Lua, for both halves", 1, true), "the blog list rendered")
    assert(not markup:find("A framework in Lua", 1, true), "the home page is gone")

    -- Writing to the old page's state must not raise and must not touch the
    -- document.
    first.scope.name = "nobody"
    assert(mock.serialize(dom.body) == markup, "the old page's effects are stopped")
    assert(session.route == "/blog")
  end)
end

function T.refuses_a_route_it_does_not_have()
  with_bundle(function(registry)
    local moonlight = require("lunar.site.moonlight")
    moonlight.install_resolver(registry)
    local defs, err = moonlight.chain_for(registry, "/not-a-route")
    assert(defs == nil)
    assert(err:find("no such route", 1, true))
  end)
end

return T
