--- A DOM in a table, for testing the browser renderer without a browser.
--
-- It implements the same backend interface `lunar.runtime.dom` expects of the
-- real one, so the generated client code runs against it unchanged. The point
-- is `serialize`: a tree built by the client renderer can be turned back into
-- markup and compared, byte for byte, with what the server renderer produced
-- for the same component and the same props.

local dom = require("lunar.runtime.dom")
local html = require("lunar.core.html")

local mock = {}

local VOID = html.VOID_ELEMENTS

local function node(kind, fields)
  local self = { kind = kind, children = {}, attributes = {}, order = {},
    properties = {}, listeners = {}, parent = nil }
  for key, value in pairs(fields or {}) do self[key] = value end
  return self
end

local function detach(child)
  local parent = child.parent
  if not parent then return end
  for index, candidate in ipairs(parent.children) do
    if candidate == child then
      table.remove(parent.children, index)
      break
    end
  end
  child.parent = nil
end

local function insert(parent, child, position)
  -- A fragment is spliced in, never inserted: that is what makes it a
  -- fragment, and the client renderer depends on it to move a block's nodes
  -- into the document in one go.
  local items = { child }
  if child.kind == "fragment" then
    items = {}
    for _, grandchild in ipairs(child.children) do items[#items + 1] = grandchild end
    child.children = {}
  end
  for offset, item in ipairs(items) do
    detach(item)
    table.insert(parent.children, position + offset - 1, item)
    item.parent = parent
  end
end

function mock.new()
  local document = node("document", { kind = "document" })
  local head = node("element", { tag = "head" })
  local body = node("element", { tag = "body" })
  insert(document, head, 1)
  insert(document, body, 2)

  local backend = {}

  function backend.create_element(tag) return node("element", { tag = tag }) end
  function backend.create_text(value) return node("text", { value = value }) end
  function backend.create_fragment() return node("fragment") end
  function backend.create_raw(markup) 
    local fragment = node("fragment")
    insert(fragment, node("raw", { value = markup }), 1)
    return fragment
  end

  function backend.append(parent, child) insert(parent, child, #parent.children + 1) end

  function backend.insert_before(parent, child, reference)
    local position = #parent.children + 1
    for index, candidate in ipairs(parent.children) do
      if candidate == reference then position = index break end
    end
    insert(parent, child, position)
  end

  function backend.parent_of(child) return child.parent end
  function backend.remove(child) detach(child) end

  function backend.children(parent)
    local out = {}
    for index, child in ipairs(parent.children) do out[index] = child end
    return out
  end

  function backend.set_attribute(element, name, value)
    if element.attributes[name] == nil then
      element.order[#element.order + 1] = name
    end
    element.attributes[name] = value
  end

  function backend.remove_attribute(element, name)
    element.attributes[name] = nil
  end

  function backend.set_text(text, value) text.value = value end
  function backend.set_property(element, name, value) element.properties[name] = value end
  function backend.property(element, name) return element.properties[name] end
  function backend.head() return head end

  function backend.listen(element, event, handler)
    local listeners = element.listeners[event] or {}
    element.listeners[event] = listeners
    listeners[#listeners + 1] = handler
    return function()
      for index, candidate in ipairs(listeners) do
        if candidate == handler then table.remove(listeners, index) return end
      end
    end
  end

  local adapter = dom.adapter(backend)
  adapter.document = document
  adapter.body = body
  -- Not `adapter.head`: `Dom:head()` is a method, and a field of that name
  -- would shadow it.
  adapter.head_element = head
  return adapter
end

--- The markup for a node, in the shape the server renderer writes it: the
-- attributes in the order they were set, no self-closing slash, nothing added.
function mock.serialize(target)
  local out = {}
  local function walk(current)
    if current.kind == "text" then
      out[#out + 1] = html.escape(current.value)
      return
    end
    if current.kind == "raw" then
      out[#out + 1] = current.value
      return
    end
    if current.kind == "element" then
      out[#out + 1] = "<" .. current.tag
      for _, name in ipairs(current.order) do
        local value = current.attributes[name]
        if value ~= nil then out[#out + 1] = html.attr(name, value) end
      end
      out[#out + 1] = ">"
      if VOID[current.tag] then return end
    end
    for _, child in ipairs(current.children) do walk(child) end
    if current.kind == "element" then
      out[#out + 1] = "</" .. current.tag .. ">"
    end
  end
  for _, child in ipairs(target.children) do walk(child) end
  return table.concat(out)
end

--- One node's own markup, including its tag. `serialize` renders a
-- container's children, which is what a mounted component is; this is for a
-- test that has a single element in hand.
function mock.outer(target)
  local holder = { kind = "fragment", children = { target } }
  return mock.serialize(holder)
end

--- Fires an event the way a browser would, including the bubble up the tree,
-- so `on:click|stop` and `|self` mean something in a test.
function mock.fire(element, event_name, fields)
  local event = { type = event_name, target = element, defaultPrevented = false }
  local stopped = false
  event.preventDefault = function(self) self.defaultPrevented = true end
  event.stopPropagation = function() stopped = true end
  for key, value in pairs(fields or {}) do event[key] = value end

  local current = element
  while current and not stopped do
    local listeners = current.listeners[event_name]
    if listeners then
      local snapshot = {}
      for index, handler in ipairs(listeners) do snapshot[index] = handler end
      for _, handler in ipairs(snapshot) do
        event.currentTarget = current
        handler(event)
        if stopped then break end
      end
    end
    current = current.parent
  end
  return event
end

--- Types into an input: sets the property and fires the event a `bind:` is
-- listening for.
function mock.input(element, value, property)
  element.properties[property or "value"] = value
  mock.fire(element, property == "checked" and "change" or "input")
end

return mock
