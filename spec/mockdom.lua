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

local function insert(parent, child, reference)
  local items = { child }
  if child.kind == "fragment" then
    items = {}
    for _, grandchild in ipairs(child.children) do items[#items + 1] = grandchild end
    child.children = {}
  end
  for _, item in ipairs(items) do detach(item) end

  local position = #parent.children + 1
  if reference then
    for index, candidate in ipairs(parent.children) do
      if candidate == reference then position = index break end
    end
  end
  for offset, item in ipairs(items) do
    table.insert(parent.children, position + offset - 1, item)
    item.parent = parent
  end
end

function mock.new()
  local document = node("document", { kind = "document" })
  local head = node("element", { tag = "head" })
  local body = node("element", { tag = "body" })
  insert(document, head)
  insert(document, body)

  local backend = {}

  function backend.create_element(tag) return node("element", { tag = tag }) end
  function backend.create_text(value) return node("text", { value = value }) end
  function backend.create_fragment() return node("fragment") end
  function backend.create_raw(markup)
    local fragment = node("fragment")
    insert(fragment, node("raw", { value = markup }))
    return fragment
  end

  function backend.append(parent, child) insert(parent, child) end

  function backend.insert_before(parent, child, reference)
    insert(parent, child, reference)
  end

  function backend.parent_of(child) return child.parent end
  function backend.remove(child) detach(child) end

  function backend.children(parent)
    local out = {}
    for index, child in ipairs(parent.children) do out[index] = child end
    return out
  end

  function backend.first_child(parent) return parent.children[1] end

  function backend.next_sibling(child)
    local parent = child.parent
    if not parent then return nil end
    for index, candidate in ipairs(parent.children) do
      if candidate == child then return parent.children[index + 1] end
    end
    return nil
  end

  function backend.node_kind(child)
    if child.kind == "element" or child.kind == "text" then return child.kind end
    return "other"
  end

  function backend.tag_name(element) return element.tag end
  function backend.text_value(text) return text.value end

  function backend.split_text(text, offset)
    local tail = node("text", { value = text.value:sub(offset + 1) })
    text.value = text.value:sub(1, offset)
    insert(text.parent, tail, backend.next_sibling(text))
    return tail
  end

  function backend.attribute(element, name) return element.attributes[name] end
  function backend.markup_of(child)
    if child.kind == "raw" then
      local holder = node("fragment")
      mock.parse_into(holder, child.value)
      return mock.serialize(holder)
    end
    return mock.outer(child)
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
  adapter.head_element = head
  return adapter
end

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

function mock.outer(target)
  local holder = { kind = "fragment", children = { target } }
  return mock.serialize(holder)
end


local RAW_TEXT = { script = true, style = true, textarea = true, title = true }

local ENTITIES = {
  ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">",
  ["&quot;"] = '"', ["&#39;"] = "'",
}

local function decode(text)
  return (text:gsub("&%#?%w+;", function(entity) return ENTITIES[entity] or entity end))
end

local function attributes_of(element, source)
  for name, value in source:gmatch('([%w:@_%-%.]+)%s*=%s*"([^"]*)"') do
    element.order[#element.order + 1] = name
    element.attributes[name] = decode(value)
  end
end

function mock.parse_into(parent, markup)
  local stack = { parent }
  local position = 1

  local function current() return stack[#stack] end

  local function text(value)
    if value == "" then return end
    insert(current(), node("text", { value = decode(value) }))
  end

  while position <= #markup do
    local from, to = markup:find("<", position, true)
    if not from then
      text(markup:sub(position))
      break
    end
    text(markup:sub(position, from - 1))

    local close_from, close_to, slash, tag, rest = markup:find("^<(/?)([%a][%w:%-]*)(.-)>", from)
    if not close_from then
      text(markup:sub(from, from))
      position = from + 1
    elseif slash == "/" then
      table.remove(stack)
      position = close_to + 1
    else
      tag = tag:lower()
      local element = node("element", { tag = tag })
      attributes_of(element, rest)
      insert(current(), element)
      position = close_to + 1
      if RAW_TEXT[tag] then
        local body_from, body_to = markup:find("</" .. tag .. "%s*>", position)
        local body = markup:sub(position, (body_from or #markup + 1) - 1)
        if body ~= "" then
          insert(element, node("text", { value = body }))
        end
        position = (body_to or #markup) + 1
      elseif not VOID[tag] then
        stack[#stack + 1] = element
      end
    end
    local _ = to
  end

  return parent
end

function mock.parse(markup)
  local adapter = mock.new()
  mock.parse_into(adapter.body, markup)
  return adapter
end

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

function mock.input(element, value, property)
  element.properties[property or "value"] = value
  mock.fire(element, property == "checked" and "change" or "input")
end

return mock
