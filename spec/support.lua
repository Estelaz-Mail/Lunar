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

function support.ssr(def, props)
  local markup, ctx = component.render(def, props or {})
  return markup, ctx
end

function support.client(def, props, options)
  local dom = mock.new()
  local instance = component.mount(def, dom.body, props or {}, {
    dom = dom, ctx = options and options.ctx or nil,
  })
  return mock.serialize(dom.body), dom, instance
end

function support.hydrate(def, props, options)
  options = options or {}
  local markup = options.markup or support.ssr(def, props or {})
  local dom = mock.parse(markup)
  local reason
  local before = support.nodes(dom.body)
  local parsed = support.serialize(dom.body)
  local counts = support.count_calls(dom)
  local instance, claimed = component.mount(def, dom.body, props or {}, {
    dom = dom, hydrate = true,
    on_rebuild = function(why) reason = why end,
  })
  return { markup = markup, dom = dom, instance = instance, claimed = claimed,
    reason = reason, before = before, counts = counts, parsed = parsed }
end

function support.nodes(target)
  local found = {}
  local function walk(node)
    found[node] = true
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(target)
  return found
end

function support.count_calls(dom)
  local counts = { created = 0, appended = 0, attributes = 0, text = 0 }
  local backend = dom.backend
  local create_element, append = backend.create_element, backend.append
  local set_attribute, set_text = backend.set_attribute, backend.set_text
  function backend.create_element(tag)
    counts.created = counts.created + 1
    return create_element(tag)
  end
  function backend.append(parent, child)
    counts.appended = counts.appended + 1
    return append(parent, child)
  end
  function backend.set_attribute(element, name, value)
    counts.attributes = counts.attributes + 1
    return set_attribute(element, name, value)
  end
  function backend.set_text(text, value)
    counts.text = counts.text + 1
    return set_text(text, value)
  end
  return counts
end

function support.assert_claims(def, props, message)
  local run = support.hydrate(def, props)
  if not run.claimed then
    error(string.format("%s\n  gave up: %s",
      message or "the page did not claim the server's nodes", tostring(run.reason)), 2)
  end
  local after = support.serialize(run.dom.body)
  if after ~= run.parsed then
    error(string.format("%s\n  document: %s\n  claimed:  %s",
      message or "hydration changed the page", run.parsed, after), 2)
  end
  for node in pairs(support.nodes(run.dom.body)) do
    if node.kind == "element" and not run.before[node] then
      error(string.format("%s\n  <%s> was built rather than claimed",
        message or "hydration rebuilt an element", node.tag), 2)
    end
  end
  if run.counts.created > 0 then
    error(string.format("%s\n  %d elements were created",
      message or "hydration created elements", run.counts.created), 2)
  end
  return run
end

function support.assert_same(def, props, message)
  local server = support.ssr(def, props)
  local browser = support.client(def, props)
  if server ~= browser then
    error(string.format("%s\n  server:  %s\n  browser: %s",
      message or "the two renderers disagree", server, browser), 2)
  end
  return server
end

function support.find(dom, tag, index)
  local found = {}
  local function walk(node)
    if node.kind == "element" and node.tag == tag then found[#found + 1] = node end
    for _, child in ipairs(node.children) do walk(child) end
  end
  walk(dom.body)
  return found[index or 1], found
end

function support.nodes_of_tag(target, tag)
  local found = {}
  local function walk(node)
    if node.kind == "element" and node.tag == tag then found[#found + 1] = node end
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(target)
  return found
end

support.fire = mock.fire
support.input = mock.input
support.serialize = mock.serialize
support.outer = mock.outer

return support
