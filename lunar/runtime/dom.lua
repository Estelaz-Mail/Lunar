local html = require("lunar.core.html")

local dom = {}

local Dom = {}
Dom.__index = Dom

function dom.adapter(backend)
  return setmetatable({ backend = backend }, Dom)
end


local function top(state) return state.stack[#state.stack] end

local function is_virtual(node)
  return type(node) == "table" and node.hydration_fragment == true
end

local function describe(backend, node)
  if node == nil then return "nothing" end
  local kind = backend.node_kind(node)
  if kind == "element" then return "<" .. backend.tag_name(node) .. ">" end
  if kind == "text" then return string.format("the text %q", backend.text_value(node)) end
  return "a " .. kind .. " node"
end

local function place(self, frame, node)
  if frame.next then
    self.backend.insert_before(frame.node, node, frame.next)
  else
    self.backend.append(frame.node, node)
  end
  self.hydration.placed[node] = true
  return node
end

local function flush_anchors(self, frame, from, to)
  for index = from, math.min(to, #frame.pending) do
    place(self, frame, frame.pending[index])
  end
  for index = math.min(to, #frame.pending), from, -1 do
    table.remove(frame.pending, index)
  end
end

local function flushable_from(state, frame)
  for index = #state.open, 1, -1 do
    if state.open[index].frame == frame then return state.open[index].mark end
  end
  return 1
end

local function claiming_frame(self)
  local state = self.hydration
  if not state or state.failed then return nil end
  local frame = top(state)
  if not frame or not frame.claiming then return nil end
  flush_anchors(self, frame, flushable_from(state, frame), #frame.pending)
  return frame, state
end

local function open_block(self, frame, state)
  flush_anchors(self, frame, flushable_from(state, frame), #frame.pending - 1)
  local block = { frame = frame, mark = #frame.pending + 1, nodes = {} }
  state.open[#state.open + 1] = block
  return block
end

local function push(state, node, claiming, cursor)
  state.stack[#state.stack + 1] =
    { node = node, next = cursor, claiming = claiming, pending = {} }
end

local function close_frame(self, state)
  local frame = top(state)
  state.stack[#state.stack] = nil
  if not frame.claiming then return end
  flush_anchors(self, frame, 1, #frame.pending)
  if frame.next ~= nil then
    self:hydration_failed(string.format(
      "the server left %s inside <%s> that the page did not build",
      describe(self.backend, frame.next), self.backend.tag_name(frame.node)))
  end
end

function Dom:claiming()
  return self.hydration ~= nil and self.hydration.failed == nil
end

function Dom:hydration_failed(reason)
  local state = self.hydration
  if not state or state.failed then return end
  state.failed = reason
  for _, frame in ipairs(state.stack) do
    flush_anchors(self, frame, 1, #frame.pending)
    frame.claiming = false
  end
end

local function claim_raw(self, frame, state, markup)
  local backend = self.backend
  local wanted = {}
  for _, node in ipairs(backend.children(backend.create_raw(markup))) do
    local piece = backend.markup_of(node)
    if not piece then return nil end
    wanted[#wanted + 1] = piece
  end
  local target = table.concat(wanted)

  local nodes, have, length = {}, {}, 0
  local candidate = frame.next
  while length < #target do
    if candidate == nil then return nil end
    local piece = backend.markup_of(candidate)
    if not piece then return nil end
    nodes[#nodes + 1] = candidate
    have[#have + 1] = piece
    length = length + #piece
    candidate = backend.next_sibling(candidate)
  end
  if table.concat(have) ~= target then return nil end

  for _, node in ipairs(nodes) do
    state.placed[node], state.claimed[node] = true, true
  end
  frame.next = candidate
  local block = open_block(self, frame, state)
  block.nodes = nodes
  return { hydration_fragment = true, nodes = nodes, frame = frame, block = block }
end

function Dom:hydrate(target, build)
  local state = { stack = {}, placed = {}, claimed = {}, dynamic = {},
    anchors = {}, open = {} }
  self.hydration = state
  push(state, target, true, self.backend.first_child(target))
  local ok, err = pcall(build)
  if ok then close_frame(self, state) end
  self.hydration = nil
  if not ok then return false, tostring(err) end
  if state.failed then return false, state.failed end
  return true
end

function Dom:element(tag)
  if not self.hydration then return self.backend.create_element(tag) end

  local frame, state = claiming_frame(self)
  if frame then
    local candidate = frame.next
    if candidate and self.backend.node_kind(candidate) == "element"
      and self.backend.tag_name(candidate) == tag then
      frame.next = self.backend.next_sibling(candidate)
      state.placed[candidate], state.claimed[candidate] = true, true
      push(state, candidate, true, self.backend.first_child(candidate))
      return candidate
    end
    self:hydration_failed(string.format("the page wanted <%s> where the server left %s",
      tag, describe(self.backend, candidate)))
  end

  local node = self.backend.create_element(tag)
  push(self.hydration, node, false, nil)
  return node
end

function Dom:text(value)
  value = value or ""
  if not self.hydration then return self.backend.create_text(value) end

  local frame, state = claiming_frame(self)
  if frame then
    local candidate = frame.next
    if candidate and self.backend.node_kind(candidate) == "text" then
      local data = self.backend.text_value(candidate)
      state.placed[candidate], state.claimed[candidate] = true, true
      if value == "" then
        frame.next = self.backend.next_sibling(candidate)
        state.dynamic[candidate] = frame
        return candidate
      elseif data == value then
        frame.next = self.backend.next_sibling(candidate)
        return candidate
      elseif #data > #value and data:sub(1, #value) == value then
        frame.next = self.backend.split_text(candidate, #value)
        return candidate
      end
      self:hydration_failed(string.format(
        "the page wanted the text %q where the server left %q", value, data))
    elseif value == "" then
      return place(self, frame, self.backend.create_text(""))
    else
      self:hydration_failed(string.format(
        "the page wanted the text %q where the server left %s",
        value, describe(self.backend, candidate)))
    end
  end

  return self.backend.create_text(value)
end

function Dom:anchor(parent)
  if self.hydration then
    local frame, state = claiming_frame(self)
    if frame then
      local node = self.backend.create_text("")
      state.anchors[node] = frame
      frame.pending[#frame.pending + 1] = node
      return node
    end
  end
  local node = self.backend.create_text("")
  self.backend.append(parent, node)
  return node
end

function Dom:fragment()
  local state = self.hydration
  if state and not state.failed then
    local frame = top(state)
    if frame and frame.claiming then
      local block = open_block(self, frame, state)
      return { hydration_fragment = true, nodes = block.nodes, frame = frame,
        block = block }
    end
  end
  return self.backend.create_fragment()
end

function Dom:append(parent, node)
  local state = self.hydration
  if state then
    local frame = top(state)
    if frame and frame.node == node then close_frame(self, state) end
    if is_virtual(parent) then
      if state.placed[node] then parent.nodes[#parent.nodes + 1] = node end
      return node
    end
    if state.placed[node] then return node end
  end
  self.backend.append(parent, node)
  return node
end

function Dom:insert_before(reference, node)
  local state = self.hydration
  if state and is_virtual(node) then
    local frame = node.frame
    for index = #state.open, 1, -1 do
      if state.open[index] == node.block then table.remove(state.open, index) break end
    end
    flush_anchors(self, frame, node.block.mark, #frame.pending)
    if state.anchors[reference] then
      place(self, frame, reference)
      for index, candidate in ipairs(frame.pending) do
        if candidate == reference then table.remove(frame.pending, index) break end
      end
    end
    return node
  end
  if state and state.placed[node] then return node end

  local parent = self.backend.parent_of(reference)
  if not parent then return node end
  self.backend.insert_before(parent, node, reference)
  return node
end

function Dom:remove(node)
  self.backend.remove(node)
end

function Dom:children(node)
  if is_virtual(node) then
    local out = {}
    for index, child in ipairs(node.nodes) do out[index] = child end
    return out
  end
  return self.backend.children(node)
end

function Dom:clear(node)
  for _, child in ipairs(self.backend.children(node)) do
    self.backend.remove(child)
  end
end

function Dom:attr(node, name, value)
  local state = self.hydration
  if state and state.claimed[node] then
    local current = self.backend.attribute(node, name)
    if value == nil or value == false then
      if current == nil then return end
    elseif value == true then
      if current == "" then return end
    elseif current == tostring(value) then
      return
    end
  end

  if value == nil or value == false then
    self.backend.remove_attribute(node, name)
  elseif value == true then
    self.backend.set_attribute(node, name, "")
  else
    self.backend.set_attribute(node, name, tostring(value))
  end
end

function Dom:spread(node, values, skip)
  if type(values) ~= "table" then return end
  for _, name in ipairs(html.attribute_names(values, skip)) do
    self:attr(node, name, values[name])
  end
end

function Dom:set_text(node, value)
  local wanted = html.plain(value)
  local state = self.hydration
  if state then
    local frame = state.dynamic[node]
    if frame then
      state.dynamic[node] = nil
      local data = self.backend.text_value(node)
      if data == wanted then return node end
      if #data > #wanted and data:sub(1, #wanted) == wanted then
        frame.next = self.backend.split_text(node, #wanted)
        return node
      end
      self:hydration_failed(string.format(
        "the page renders the text %q where the server rendered %q", wanted, data))
    elseif state.claimed[node] and self.backend.node_kind(node) == "element" then
      local frame_now = top(state)
      if frame_now and frame_now.node == node then frame_now.next = nil end
    end
  end
  self.backend.set_text(node, wanted)
  return node
end

function Dom:raw(markup)
  local text = html.plain(markup)
  local state = self.hydration
  if state and not state.failed then
    local frame = top(state)
    if frame and frame.claiming then
      local claimed = claim_raw(self, frame, state, text)
      if claimed then return claimed end
      self:hydration_failed("the markup of an {@html} is not what the server left")
    end
  end
  return self.backend.create_raw(text)
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

function dom.bind_event(name)
  if name == "checked" then return "change" end
  if name == "value" then return "input" end
  return "change"
end

dom.Dom = Dom

function dom.browser(window, js)
  local document = window.document

  local function present(value)
    if value == nil or value == js.null then return nil end
    return value
  end

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
    local child = present(node.firstChild)
    while child do
      out[#out + 1] = child
      child = present(child.nextSibling)
    end
    return out
  end
  function backend.set_attribute(node, name, value) node:setAttribute(name, value) end
  function backend.remove_attribute(node, name) node:removeAttribute(name) end
  function backend.attribute(node, name)
    local value = present(node:getAttribute(name))
    if value == nil then return nil end
    return tostring(value)
  end
  function backend.set_text(node, value) node.textContent = value end
  function backend.set_property(node, name, value) node[name] = value end
  function backend.property(node, name) return node[name] end
  function backend.head() return document.head end

  function backend.first_child(node) return present(node.firstChild) end
  function backend.next_sibling(node) return present(node.nextSibling) end

  function backend.node_kind(node)
    local kind = node.nodeType
    if kind == 1 then return "element" end
    if kind == 3 then return "text" end
    return "other"
  end

  function backend.tag_name(node) return tostring(node.tagName):lower() end
  function backend.text_value(node) return tostring(node.data) end
  function backend.split_text(node, offset)
    local units = 0
    for _, code in utf8.codes(tostring(node.data):sub(1, offset)) do
      units = units + (code > 65535 and 2 or 1)
    end
    return node:splitText(units)
  end

  function backend.markup_of(node)
    local kind = backend.node_kind(node)
    if kind == "element" then return tostring(node.outerHTML) end
    if kind == "text" then
      return (tostring(node.data):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end
    return nil
  end

  function backend.create_raw(markup)
    local template = document:createElement("template")
    template.innerHTML = markup
    return template.content
  end

  function backend.listen(node, event, handler, options)
    local listener_options = nil
    if options and (options.capture or options.passive) then
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
