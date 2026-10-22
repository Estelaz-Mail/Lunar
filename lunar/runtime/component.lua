local scope_lib = require("lunar.runtime.scope")
local signal = require("lunar.runtime.signal")

local component = {}

local Instance = {}
Instance.__index = Instance

component.resolver = nil

function component.define(spec)
  assert(type(spec.setup) == "function", "lunar: a component needs a setup function")
  spec.lunar_component = true
  spec.name = spec.name or "component"
  return spec
end

function component.is(value)
  return type(value) == "table" and value.lunar_component == true
end

local function builtins_for(instance)
  local declared = {}

  local function register_effect(fn)
    local dispose = signal.effect(fn)
    instance.disposers[#instance.disposers + 1] = dispose
    return dispose
  end

  return {
    props = function(defaults)
      for name, value in pairs(defaults or {}) do
        declared[name] = true
        if instance.props[name] == nil then
          scope_lib.put(instance, name, value)
        end
      end
      instance.declared_props = declared
    end,

    watch = register_effect,

    derived = function(name, fn)
      if type(name) ~= "string" or type(fn) ~= "function" then
        error("lunar: derived(name, fn) wants a name and a function", 2)
      end
      register_effect(function() scope_lib.put(instance, name, fn()) end)
    end,

    on_rise = function(fn)
      instance.rise_hooks[#instance.rise_hooks + 1] = fn
    end,

    on_set = function(fn)
      instance.set_hooks[#instance.set_hooks + 1] = fn
    end,

    set_context = function(key, value)
      instance.contexts[key] = value
    end,

    get_context = function(key)
      local node = instance
      while node do
        local value = node.contexts[key]
        if value ~= nil then return value end
        node = node.parent
      end
      return nil
    end,

    import = function(path)
      if not component.resolver then
        error("lunar: import() needs a resolver; the app server sets one", 2)
      end
      local resolved, err = component.resolver(path, instance.def.path)
      if not resolved then
        error(string.format("lunar: cannot import %s: %s", path, tostring(err or "not found")), 2)
      end
      return resolved
    end,

    lunar = instance,
  }
end

local function slot_table(slot)
  if slot == nil then return nil end
  if type(slot) == "function" then return { default = slot } end
  return slot
end

function component.create(def, props, options)
  options = options or {}
  local instance = setmetatable({
    def = def,
    props = props or {},
    parent = options.parent,
    ctx = options.ctx or (options.parent and options.parent.ctx) or {},
    slots = slot_table(options.slot),
    dom = options.dom or (options.parent and options.parent.dom),
    client = options.client or (options.parent and options.parent.client) or false,
    signals = {},
    contexts = {},
    disposers = {},
    rise_hooks = {},
    set_hooks = {},
    nodes = {},
    children = {},
    owners = {},
  }, Instance)

  for name, value in pairs(instance.props) do
    scope_lib.put(instance, name, value)
  end

  instance.builtins = builtins_for(instance)
  instance.scope = scope_lib.new(instance, instance.builtins)

  if def.css and instance.ctx.css then
    instance.ctx.css[def.scope_class or def.name] = def.css
  end

  local ok, render_ssr, render_client = pcall(def.setup, instance.scope)
  if not ok then
    error(string.format("lunar: %s: %s", def.name, tostring(render_ssr)), 0)
  end
  instance.render_ssr = render_ssr
  instance.render_client = render_client

  return instance
end

function Instance:set_props(props)
  signal.batch(function()
    for name, value in pairs(props) do
      self.props[name] = value
      scope_lib.put(self, name, value)
    end
  end)
end

function Instance:destroy()
  for index = #self.set_hooks, 1, -1 do
    local ok, err = pcall(self.set_hooks[index])
    if not ok then io.stderr:write("lunar: an on_set hook failed: ", tostring(err), "\n") end
  end
  for _, dispose in ipairs(self.disposers) do dispose() end
  self.disposers = {}
  for _, child in ipairs(self.children or {}) do child:destroy() end
  self.children = nil
end

function Instance:run_rise_hooks()
  for _, hook in ipairs(self.rise_hooks) do
    local ok, err = pcall(hook)
    if not ok then io.stderr:write("lunar: an on_rise hook failed: ", tostring(err), "\n") end
    if ok and type(err) == "function" then
      self.set_hooks[#self.set_hooks + 1] = err
    end
  end
end

function component.context(fields)
  local ctx = fields or {}
  ctx.css = ctx.css or {}
  ctx.head = ctx.head or {}
  ctx.depth = ctx.depth or 0
  return ctx
end

function component.render(def, props, options)
  options = options or {}
  local ctx = options.ctx or component.context()
  local instance = component.create(def, props, {
    ctx = ctx, parent = options.parent, slot = options.slot,
  })
  local out = {}
  local ok, err = pcall(instance.render_ssr, out, instance)
  instance:destroy()
  if not ok then
    error(string.format("lunar: %s: %s", def.name, tostring(err)), 0)
  end
  return table.concat(out), ctx
end

function component.render_child(parent, def, props, slot)
  if not component.is(def) then
    error("lunar: <" .. tostring(def) .. "> is not a component", 0)
  end
  local instance = component.create(def, props, {
    parent = parent, ctx = parent.ctx, slot = slot,
  })
  local out = {}
  local ok, err = pcall(instance.render_ssr, out, instance)
  instance:destroy()
  if not ok then error(err, 0) end
  return table.concat(out)
end

function component.render_slot(instance, out, fallback, name)
  local build = instance.slots and instance.slots[name or "default"]
  if build then
    build(out)
  elseif fallback then
    fallback(out)
  end
end


local function current_owner(instance)
  return instance.owners[#instance.owners] or instance
end

local function dispose_owner(owner)
  for _, child in ipairs(owner.children or {}) do child:destroy() end
  owner.children = {}
  for _, dispose in ipairs(owner.disposers or {}) do dispose() end
  owner.disposers = {}
end

function Instance:with_owner(owner, fn)
  self.owners[#self.owners + 1] = owner
  local ok, err = pcall(fn)
  self.owners[#self.owners] = nil
  if not ok then error(err, 0) end
end

function component.effect(instance, fn)
  local owner = current_owner(instance)
  local dispose = signal.effect(fn)
  owner.disposers[#owner.disposers + 1] = dispose
  return dispose
end

function component.merge(base, extra)
  if type(extra) ~= "table" then return base end
  local out = {}
  for key, value in pairs(base or {}) do out[key] = value end
  for key, value in pairs(extra) do out[key] = value end
  return out
end

local function render_block(instance, dom, anchor, state, build, ...)
  local owner = { disposers = {}, children = {} }
  local arguments = table.pack(...)
  instance:with_owner(owner, function()
    local fragment = dom:fragment()
    build(fragment, table.unpack(arguments, 1, arguments.n))
    local nodes = dom:children(fragment)
    dom:insert_before(anchor, fragment)
    for _, node in ipairs(nodes) do state.nodes[#state.nodes + 1] = node end
  end)
  state.owners[#state.owners + 1] = owner
end

local function clear_block(dom, state)
  if #state.nodes > 0 and dom:claiming() then
    dom:hydration_failed("a block re-rendered while the page was being claimed")
  end
  for _, owner in ipairs(state.owners) do dispose_owner(owner) end
  state.owners = {}
  for _, node in ipairs(state.nodes) do dom:remove(node) end
  state.nodes = {}
end

local function new_block_state()
  return { nodes = {}, owners = {} }
end

local function own_block(instance, dom, state)
  local owner = current_owner(instance)
  owner.disposers[#owner.disposers + 1] = function() clear_block(dom, state) end
end

function component.branch(instance, dom, anchor, selector, builders)
  local state = new_block_state()
  state.index = nil
  own_block(instance, dom, state)
  component.effect(instance, function()
    local index = selector()
    if index == state.index then return end
    state.index = index
    signal.untrack(function()
      clear_block(dom, state)
      local build = builders[index]
      if build then render_block(instance, dom, anchor, state, build) end
    end)
  end)
end

function component.each(instance, dom, anchor, list_fn, item_builder, empty_builder)
  local ssr = require("lunar.runtime.ssr")
  local state = new_block_state()
  own_block(instance, dom, state)
  component.effect(instance, function()
    local list = ssr.list(list_fn())
    signal.untrack(function()
      clear_block(dom, state)
      if #list == 0 then
        if empty_builder then render_block(instance, dom, anchor, state, empty_builder) end
        return
      end
      for index, item in ipairs(list) do
        render_block(instance, dom, anchor, state, item_builder, item, index)
      end
    end)
  end)
end

function component.html(instance, dom, anchor, value_fn)
  local state = new_block_state()
  own_block(instance, dom, state)
  component.effect(instance, function()
    local markup = value_fn()
    signal.untrack(function()
      clear_block(dom, state)
      local fragment = dom:raw(markup)
      local nodes = dom:children(fragment)
      dom:insert_before(anchor, fragment)
      state.nodes = nodes
    end)
  end)
end

function component.child(instance, dom, parent_node, def, props_fn, slot_builder)
  if not component.is(def) then
    error("lunar: <" .. tostring(def) .. "> is not a component", 0)
  end
  local child = component.create(def, signal.untrack(props_fn), {
    parent = instance, dom = dom, client = true,
  })
  child.slots_client = slot_table(slot_builder)
  current_owner(instance).children[#current_owner(instance).children + 1] = child

  child:with_owner(child, function()
    child.render_client(parent_node, child)
  end)

  local subscribed = false
  component.effect(instance, function()
    local props = props_fn()
    if not subscribed then
      subscribed = true
      return
    end
    signal.untrack(function() child:set_props(props) end)
  end)

  child:run_rise_hooks()
  return child
end

function component.slot(instance, dom, parent_node, fallback, name)
  local build = instance.slots_client and instance.slots_client[name or "default"]
  if build then
    build(parent_node)
  elseif fallback then
    fallback(parent_node)
  end
end

function component.head(instance, dom, build)
  if not (instance.ctx and instance.ctx.render_head) then return end
  local head = dom:head()
  if not head then return end
  local fragment = dom:fragment()
  build(fragment)
  local nodes = dom:children(fragment)
  dom:append(head, fragment)
  instance.set_hooks[#instance.set_hooks + 1] = function()
    for _, node in ipairs(nodes) do dom:remove(node) end
  end
end

function component.bind(instance, dom, node, name, get, set)
  local dom_lib = require("lunar.runtime.dom")
  component.effect(instance, function()
    local value = get()
    if value == nil then return end
    dom:set_property(node, name, value)
    if name == "checked" then
      dom:attr(node, "checked", value and true or nil)
    else
      dom:attr(node, name, value)
    end
  end)
  local remove = dom:on(node, dom_lib.bind_event(name), function()
    set(dom:property(node, name))
  end, {})
  current_owner(instance).disposers[#current_owner(instance).disposers + 1] = remove
end

function component.mount(def, target, props, options)
  options = options or {}
  local dom = options.dom
  local ctx = options.ctx or component.context()

  local function render()
    local instance = component.create(def, props, { dom = dom, client = true, ctx = ctx })
    instance:with_owner(instance, function()
      instance.render_client(target, instance)
    end)
    return instance
  end

  if options.hydrate then
    local instance
    local claimed, reason = dom:hydrate(target, function() instance = render() end)
    if claimed then
      instance:run_rise_hooks()
      return instance, true
    end
    if instance then instance:destroy() end
    if options.on_rebuild then options.on_rebuild(reason) end
  end

  dom:clear(target)
  local instance = render()
  instance:run_rise_hooks()
  return instance, false
end

component.Instance = Instance

return component
