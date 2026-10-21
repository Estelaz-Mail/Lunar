--- Shared test helpers: compile a fixture, render it both ways.

local compiler = require("lunar.compiler")
local component = require("lunar.runtime.component")
local mock = require("mockdom")

local support = {}

support.FIXTURES = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or ".")
  .. "/fixtures"

function support.cache()
  return compiler.cache({ root = support.FIXTURES, watch = true }):install()
end

function support.component(name)
  local cache = support.cache()
  local def, err = cache:get(support.FIXTURES .. "/" .. name .. ".lunar")
  assert(def, err)
  return def
end

function support.source(source, path)
  local def = compiler.load(source, { path = path or "Fixture.lunar" })
  return def
end

--- Renders on the server.
function support.ssr(def, props)
  local markup, ctx = component.render(def, props or {})
  return markup, ctx
end

--- Renders in the browser, into a DOM made of tables. Returns the markup, the
-- adapter and the instance, so a test can fire an event and look again.
function support.client(def, props, options)
  local dom = mock.new()
  local instance = component.mount(def, dom.body, props or {}, {
    dom = dom, ctx = options and options.ctx or nil,
  })
  return mock.serialize(dom.body), dom, instance
end

--- The assertion this whole framework rests on: the same component, the same
-- props, the same markup, whichever renderer produced it.
function support.assert_same(def, props, message)
  local server = support.ssr(def, props)
  local browser = support.client(def, props)
  if server ~= browser then
    error(string.format("%s\n  server:  %s\n  browser: %s",
      message or "the two renderers disagree", server, browser), 2)
  end
  return server
end

--- Finds the first element with a tag, for a test that needs to click it.
function support.find(dom, tag, index)
  local found = {}
  local function walk(node)
    if node.kind == "element" and node.tag == tag then found[#found + 1] = node end
    for _, child in ipairs(node.children) do walk(child) end
  end
  walk(dom.body)
  return found[index or 1], found
end

support.fire = mock.fire
support.input = mock.input
support.serialize = mock.serialize
support.outer = mock.outer

return support
