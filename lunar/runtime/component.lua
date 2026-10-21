--- Component instances: props, context, lifecycle, and the two renderers.
--
-- A compiled `.lunar` file returns `define{...}` with three functions the
-- generator wrote — `setup`, `ssr` and `client` — and the metadata the page
-- needs. Everything else about a component lives here, so the generated code
-- stays a thin transcription of the template.

local scope_lib = require("lunar.runtime.scope")
local signal = require("lunar.runtime.signal")

local component = {}

local Instance = {}
Instance.__index = Instance

--- How `import("./Card.lunar")` finds a component. The server sets this to the
-- compiler's cache; the browser bundle sets it to its registry. Without one,
-- a component that imports another says so instead of failing at the call.
component.resolver = nil

--- A compiled component. `setup` runs the `<script>` and returns the two
-- renderers, which are closures inside it: that is how a template sees the
-- script's locals.
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
    --- Declares props and their defaults. Props that were passed in are
    -- already state by the time this runs, so this only fills the gaps.
    props = function(defaults)
      for name, value in pairs(defaults or {}) do
        declared[name] = true
        if instance.props[name] == nil then
          scope_lib.put(instance, name, value)
        end
      end
      instance.declared_props = declared
    end,

    --- Runs now, and again whenever anything it read changes. This is both
    -- the side-effect escape hatch and the way to write derived state:
    -- `watch(function() total = price * count end)`.
    watch = register_effect,

    --- A named value computed from state. `derived("doubled", fn)` keeps
    -- `doubled` up to date; the template reads it like any other state.
    derived = function(name, fn)
      if type(name) ~= "string" or type(fn) ~= "function" then
        error("lunar: derived(name, fn) wants a name and a function", 2)
      end
      register_effect(function() scope_lib.put(instance, name, fn()) end)
    end,

    --- Moonrise: the component is in the document. Browser only — on the
    -- server it is recorded and never runs, which is what makes this the
    -- right place for anything that touches the DOM. Return a function and it
    -- becomes the matching `on_set`.
    on_rise = function(fn)
      instance.rise_hooks[#instance.rise_hooks + 1] = fn
    end,

    --- Moonset: the component is about to be removed.
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

    --- Another component, by path, relative to this one.
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

    --- The current instance, for the rare case a helper needs it.
    lunar = instance,
  }
end

--- Builds an instance and runs its `<script>`. `options` is
-- `{ parent, ctx, slot, dom, client }`.
function component.create(def, props, options)
  options = options or {}
  local instance = setmetatable({
    def = def,
    props = props or {},
    parent = options.parent,
    ctx = options.ctx or (options.parent and options.parent.ctx) or {},
    slot = options.slot,
    dom = options.dom or (options.parent and options.parent.dom),
    client = options.client or (options.parent and options.parent.client) or false,
    signals = {},
    contexts = {},
    disposers = {},
    rise_hooks = {},
    set_hooks = {},
    nodes = {},
    -- An instance is also an owner: the effects and children created outside
    -- any block belong to it.
    children = {},
    owners = {},
  }, Instance)

  -- Props become state before the script runs, so the script sees them and a
  -- later `props{...}` only fills in what was not passed.
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

--- Replaces the props of a live instance, which is how a parent's state
-- reaches a child.
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
      -- A rise hook may hand back the undoing of whatever it did, which is
      -- the shortest way to write a listener that has to be removed again.
      self.set_hooks[#self.set_hooks + 1] = err
    end
  end
end

--- A fresh render context: what the page collects while it renders.
function component.context(fields)
  local ctx = fields or {}
  ctx.css = ctx.css or {}
  ctx.head = ctx.head or {}
  ctx.depth = ctx.depth or 0
  return ctx
end

--- Renders to a string. This is the server half; nothing here touches a DOM.
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

--- A child component inside another component's server render.
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

--- `<slot />` on the server: the parent's children, rendered in the parent's
-- own scope, which is where they were written.
function component.render_slot(instance, out, fallback)
  if instance.slot then
    instance.slot(out)
  elseif fallback then
    fallback(out)
  end
end

-- The browser half ------------------------------------------------------------
--
-- Everything below runs only in a browser (or in a spec, against the mock DOM
-- backend). The shape is the same in both: a block owns the nodes and the
-- effects it created, and re-rendering a block disposes of them before it
-- builds again. Without that, a list that re-renders every second leaks an
-- effect per item per second.

--- An owner is whatever a newly created effect or child belongs to: the
-- instance, or the block currently being built inside it.
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

--- An effect that belongs to the block it was created in.
function component.effect(instance, fn)
  local owner = current_owner(instance)
  local dispose = signal.effect(fn)
  owner.disposers[#owner.disposers + 1] = dispose
  return dispose
end

--- Shallow merge, for `{...spread}` on an element or a component.
function component.merge(base, extra)
  if type(extra) ~= "table" then return base end
  local out = {}
  for key, value in pairs(base or {}) do out[key] = value end
  for key, value in pairs(extra) do out[key] = value end
  return out
end

--- Builds a block's content into a fragment and puts it before the anchor,
-- remembering the nodes and the effects so the next render can undo them.
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
  for _, owner in ipairs(state.owners) do dispose_owner(owner) end
  state.owners = {}
  for _, node in ipairs(state.nodes) do dom:remove(node) end
  state.nodes = {}
end

local function new_block_state()
  return { nodes = {}, owners = {} }
end

--- A block's content belongs to whatever created the block: destroying the
-- component, or re-rendering the block around it, has to take the nodes and
-- the effects inside with it. The effect that drives the block is registered
-- separately, by `component.effect`.
local function own_block(instance, dom, state)
  local owner = current_owner(instance)
  owner.disposers[#owner.disposers + 1] = function() clear_block(dom, state) end
end

--- `{#if}`. The condition is read inside the effect, so the block re-renders
-- when the branch changes; the branch's own content is built untracked, so a
-- text node inside it patches itself instead of rebuilding everything around
-- it.
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

--- `{#each}`. The list is the dependency; the items are not. A list that is
-- replaced re-renders the block, and a value inside an item that is itself
-- state patches on its own.
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

--- `{@html}`. The markup is parsed once per change and replaced as a unit.
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

--- A child component in the browser. The props are read inside an effect, so
-- the parent's state reaches the child without the child knowing about it.
function component.child(instance, dom, parent_node, def, props_fn, slot_builder)
  if not component.is(def) then
    error("lunar: <" .. tostring(def) .. "> is not a component", 0)
  end
  local child = component.create(def, signal.untrack(props_fn), {
    parent = instance, dom = dom, client = true,
  })
  child.slot_client = slot_builder
  current_owner(instance).children[#current_owner(instance).children + 1] = child

  child:with_owner(child, function()
    child.render_client(parent_node, child)
  end)

  component.effect(instance, function()
    local props = props_fn()
    signal.untrack(function() child:set_props(props) end)
  end)

  child:run_rise_hooks()
  return child
end

--- `<slot />` in the browser: the parent's children, built by the closure the
-- parent created, so they see the parent's state.
function component.slot(instance, dom, parent_node, fallback)
  if instance.slot_client then
    instance.slot_client(parent_node)
  elseif fallback then
    fallback(parent_node)
  end
end

--- `<lunar:head>` in the browser. On the first mount the head the server sent
-- is already correct and rebuilding it would duplicate every tag, so this only
-- runs for a page the browser navigated to on its own.
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

--- `bind:value` and friends: state to the element in an effect, the element
-- back to state on the event that element changes on.
function component.bind(instance, dom, node, name, get, set)
  local dom_lib = require("lunar.runtime.dom")
  component.effect(instance, function()
    local value = get()
    if value == nil then return end
    dom:set_property(node, name, value)
    -- Reflected to the attribute as well, so the element in the browser has
    -- the markup the server sent for it. A bound input is the one place the
    -- two renderers would otherwise disagree, because a value lives in a
    -- property and markup only has attributes.
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

--- Mounts a component into an element. The container's contents are replaced:
-- the server's markup was the first paint, and this is the takeover.
function component.mount(def, target, props, options)
  options = options or {}
  local dom = options.dom
  local instance = component.create(def, props, {
    dom = dom, client = true, ctx = options.ctx or component.context(),
  })
  dom:clear(target)
  instance:with_owner(instance, function()
    instance.render_client(target, instance)
  end)
  instance:run_rise_hooks()
  return instance
end

component.Instance = Instance

return component
