--- The node operations, over a backend.
--
-- The generated client code never touches a browser API directly: it calls
-- methods on one of these. In the browser the backend is Fengari's view of
-- `document`; in the specs it is a few hundred lines of Lua holding a tree of
-- tables. That is not a testing convenience bolted on afterwards — it is the
-- only way the client renderer can be checked against the server renderer
-- without a browser in the loop, and `spec/render_spec.lua` does exactly that
-- for every fixture.
--
-- A backend provides the primitives (create, append, remove, set). Everything
-- above them — anchors, event modifiers, attribute shapes — is here, once, so
-- both backends behave the same by construction.

local html = require("lunar.core.html")

local dom = {}

local Dom = {}
Dom.__index = Dom

function dom.adapter(backend)
  return setmetatable({ backend = backend }, Dom)
end

function Dom:element(tag)
  return self.backend.create_element(tag)
end

function Dom:text(value)
  return self.backend.create_text(value or "")
end

--- A position marker. An empty text node, not a comment: it occupies a
-- position in the tree and serialises to nothing, so a container built in the
-- browser has the same markup as the one the server sent.
function Dom:anchor(parent)
  local node = self.backend.create_text("")
  self.backend.append(parent, node)
  return node
end

function Dom:fragment()
  return self.backend.create_fragment()
end

function Dom:append(parent, node)
  self.backend.append(parent, node)
  return node
end

function Dom:insert_before(reference, node)
  local parent = self.backend.parent_of(reference)
  if not parent then return node end
  self.backend.insert_before(parent, node, reference)
  return node
end

function Dom:remove(node)
  self.backend.remove(node)
end

function Dom:children(node)
  return self.backend.children(node)
end

function Dom:clear(node)
  for _, child in ipairs(self.backend.children(node)) do
    self.backend.remove(child)
  end
end

--- One attribute, with HTML's boolean behaviour: `false` and `nil` remove it,
-- `true` sets it with no value.
function Dom:attr(node, name, value)
  if value == nil or value == false then
    self.backend.remove_attribute(node, name)
  elseif value == true then
    self.backend.set_attribute(node, name, "")
  else
    self.backend.set_attribute(node, name, tostring(value))
  end
end

--- `{...table}`. The names are sorted, like the server's, because the order
-- attributes are set in is the order they appear in — and the two renderers
-- have to produce the same markup. `pairs` would not: Lua's table order is
-- not the same twice.
function Dom:spread(node, values, skip)
  if type(values) ~= "table" then return end
  for _, name in ipairs(html.attribute_names(values, skip)) do
    self:attr(node, name, values[name])
  end
end

function Dom:set_text(node, value)
  self.backend.set_text(node, html.plain(value))
end

--- The nodes of a `{@html}`, as one unit so they can be replaced together.
function Dom:raw(markup)
  return self.backend.create_raw(html.plain(markup))
end

function Dom:set_property(node, name, value)
  self.backend.set_property(node, name, value)
end

function Dom:property(node, name)
  return self.backend.property(node, name)
end

function Dom:head()
  return self.backend.head()
end

--- An event listener, with the modifiers the template asked for. Returns the
-- function that removes it, which the owning effect holds on to.
function Dom:on(node, event, handler, modifiers)
  local options = {}
  local prevent, stop, once, only_self = false, false, false, false
  for _, modifier in ipairs(modifiers or {}) do
    if modifier == "prevent" then prevent = true
    elseif modifier == "stop" then stop = true
    elseif modifier == "once" then once = true
    elseif modifier == "self_" then only_self = true
    elseif modifier == "capture" then options.capture = true
    elseif modifier == "passive" then options.passive = true
    elseif modifier == "trusted" then options.trusted = true
    end
  end

  local remove
  local fired = false
  local function wrapped(event_object)
    if options.trusted and event_object and event_object.isTrusted == false then return end
    if only_self and event_object
      and event_object.target ~= nil and event_object.target ~= node then
      return
    end
    if prevent and event_object and event_object.preventDefault then
      event_object:preventDefault()
    end
    if stop and event_object and event_object.stopPropagation then
      event_object:stopPropagation()
    end
    if once then
      if fired then return end
      fired = true
      if remove then remove() end
    end
    return handler(event_object)
  end

  remove = self.backend.listen(node, event, wrapped, options)
  return remove
end

--- Which event a `bind:` listens to. `value` on a text input changes on every
-- keystroke; a checkbox and a select change on commit.
function dom.bind_event(name)
  if name == "checked" then return "change" end
  if name == "value" then return "input" end
  return "change"
end

dom.Dom = Dom

--- The browser backend, over Fengari's `js` interop. Only built when asked
-- for, so requiring this module on the server costs nothing.
--
-- `js` is Fengari's interop module, passed in rather than required, so this
-- file still loads in a plain Lua state — which is what lets the specs
-- require it next to the mock backend.
function dom.browser(window, js)
  local document = window.document

  local backend = {}

  function backend.create_element(tag) return document:createElement(tag) end
  function backend.create_text(value) return document:createTextNode(value) end
  function backend.create_fragment() return document:createDocumentFragment() end
  function backend.append(parent, node) parent:appendChild(node) end
  function backend.insert_before(parent, node, reference)
    parent:insertBefore(node, reference)
  end
  function backend.parent_of(node) return node.parentNode end
  function backend.remove(node)
    if node.parentNode then node.parentNode:removeChild(node) end
  end
  function backend.children(node)
    local out = {}
    local child = node.firstChild
    while child do
      out[#out + 1] = child
      child = child.nextSibling
    end
    return out
  end
  function backend.set_attribute(node, name, value) node:setAttribute(name, value) end
  function backend.remove_attribute(node, name) node:removeAttribute(name) end
  function backend.set_text(node, value) node.textContent = value end
  function backend.set_property(node, name, value) node[name] = value end
  function backend.property(node, name) return node[name] end
  function backend.head() return document.head end

  --- `{@html}`: parsed once in a detached template, then moved. The nodes are
  -- wrapped in a fragment so the caller can treat them as one.
  function backend.create_raw(markup)
    local template = document:createElement("template")
    template.innerHTML = markup
    return template.content
  end

  function backend.listen(node, event, handler, options)
    local listener_options = nil
    if options and (options.capture or options.passive) then
      -- A plain JS object, built through the interop. Never `eval`: the
      -- Content Security Policy this framework ships forbids it, and a
      -- framework that needs an exception to its own policy has the wrong
      -- policy or the wrong code.
      listener_options = js.new(window.Object)
      listener_options.capture = options.capture or false
      listener_options.passive = options.passive or false
    end
    node:addEventListener(event, handler, listener_options)
    return function() node:removeEventListener(event, handler, listener_options) end
  end

  return dom.adapter(backend)
end

return dom
