local component = require("lunar.runtime.component")
local resolve = require("lunar.compiler.resolve")

local moonlight = {}

function moonlight.install_resolver(registry)
  component.resolver = resolve.registry_resolver(registry)
end

function moonlight.chain_for(registry, route)
  local paths = registry.routes[route]
  if not paths then return nil, "no such route in the bundle: " .. tostring(route) end
  local defs = {}
  for index, path in ipairs(paths) do
    local name = registry.components[path]
    if not name then return nil, path .. " is not in the moonlight bundle" end
    local ok, def = pcall(require, name)
    if not ok then return nil, tostring(def) end
    defs[index] = def
  end
  return defs
end

function moonlight.mount_chain(defs, data, target, dom, options)
  options = options or {}

  local function render()
    local ctx = component.context({ render_head = options.render_head or false })
    local instances = {}

    local function build(index)
      return function(parent)
        local def = defs[index]
        local instance = component.create(def, {
          data = data[index] or {}, params = options.params or {},
        }, { dom = dom, client = true, ctx = ctx })
        instance.slots_client = index < #defs and { default = build(index + 1) } or nil
        instance:with_owner(instance, function()
          instance.render_client(parent, instance)
        end)
        instances[#instances + 1] = instance
        return instance
      end
    end

    if #defs == 0 then return nil, instances end
    return build(1)(target), instances
  end

  local function rise(instances)
    for _, instance in ipairs(instances) do instance:run_rise_hooks() end
  end

  if options.hydrate and #defs > 0 then
    local root, instances
    local claimed, reason = dom:hydrate(target, function() root, instances = render() end)
    if claimed then
      rise(instances)
      return root, instances, true
    end
    for index = #(instances or {}), 1, -1 do instances[index]:destroy() end
    if options.on_rebuild then options.on_rebuild(reason) end
  end

  dom:clear(target)
  local root, instances = render()
  rise(instances)
  return root, instances, false
end

local Session = {}
Session.__index = Session

function moonlight.start(registry, payload, dom, target, options)
  moonlight.install_resolver(registry)
  local session = setmetatable({
    registry = registry, dom = dom, target = target,
    options = options or {},
  }, Session)
  session.generation = 0
  session:swap(payload)
  return session
end

function Session:swap(payload)
  local defs, err = moonlight.chain_for(self.registry, payload.route)
  if not defs then return nil, err end

  if self.instances then
    for index = #self.instances, 1, -1 do self.instances[index]:destroy() end
  end

  local _, instances, claimed = moonlight.mount_chain(defs, payload.data or {},
    self.target, self.dom, {
      params = payload.params or {},
      render_head = self.started or false,
      hydrate = not self.started and #self.dom:children(self.target) > 0,
      on_rebuild = self.options.on_rebuild,
    })
  self.instances = instances
  if not self.started then self.hydrated = claimed end
  self.started = true
  self.route = payload.route
  return true
end

function Session:begin_navigation(path)
  self.generation = self.generation + 1
  self.pending = { generation = self.generation, path = path }
  return self.generation
end

function Session:is_current(generation)
  return generation == self.generation
end

function Session:apply(generation, payload)
  if not self:is_current(generation) then return false, "superseded" end
  local ok, err = self:swap(payload)
  if not ok then return false, err end
  self.pending = nil
  return true
end

function Session:cancel()
  self.generation = self.generation + 1
  self.pending = nil
end

moonlight.Session = Session

return moonlight
