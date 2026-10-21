--- Moonlight: the app in the browser, with no browser in it.
--
-- The server draws the page and the browser takes it over — the same
-- components, the same state, the same Lua. This module is the half that
-- takes over: it finds the route's components in the bundle, mounts them into
-- the container the server filled, and swaps them for another route's when a
-- link is followed.
--
-- Everything here works through the DOM adapter and a plain table of data, so
-- it runs under Fengari in a page and under the mock DOM in a spec. The parts
-- that genuinely need a browser — the `js` interop, `fetch`, the History API —
-- are in `lunar.site.boot`, the only file in the framework that cannot be
-- tested without one.

local component = require("lunar.runtime.component")
local resolve = require("lunar.compiler.resolve")

local moonlight = {}

--- Teaches `import()` to find a component in the moonlight registry rather
-- than on a disk the browser does not have.
function moonlight.install_resolver(registry)
  component.resolver = resolve.registry_resolver(registry)
end

--- The components of a route, outermost first.
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

--- Mounts a chain into a container, each level rendering the next into its
-- `<slot />`. This is the same composition the server does, built out of the
-- same two calls.
function moonlight.mount_chain(defs, data, target, dom, options)
  options = options or {}
  local ctx = component.context({ render_head = options.render_head or false })
  local instances = {}

  local function build(index)
    return function(parent)
      local def = defs[index]
      local instance = component.create(def, {
        data = data[index] or {}, params = options.params or {},
      }, { dom = dom, client = true, ctx = ctx })
      instance.slot_client = index < #defs and build(index + 1) or nil
      instance:with_owner(instance, function()
        instance.render_client(parent, instance)
      end)
      instance:run_rise_hooks()
      instances[#instances + 1] = instance
      return instance
    end
  end

  dom:clear(target)
  if #defs == 0 then return nil, instances end
  local root = build(1)(target)
  return root, instances
end

--- One mounted page. `swap` replaces it with another route's, which is what a
-- client-side navigation is.
local Session = {}
Session.__index = Session

function moonlight.start(registry, payload, dom, target, options)
  moonlight.install_resolver(registry)
  local session = setmetatable({
    registry = registry, dom = dom, target = target,
    options = options or {},
  }, Session)
  session:swap(payload)
  return session
end

function Session:swap(payload)
  local defs, err = moonlight.chain_for(self.registry, payload.route)
  if not defs then return nil, err end

  -- The old page's effects and listeners go before the new page's nodes
  -- arrive: a navigation that left the previous route's effects running would
  -- keep patching nodes that are no longer in the document.
  if self.instances then
    for index = #self.instances, 1, -1 do self.instances[index]:destroy() end
  end

  local _, instances = moonlight.mount_chain(defs, payload.data or {}, self.target, self.dom, {
    params = payload.params or {},
    -- The first page's head came from the server; a navigated-to page has to
    -- render its own.
    render_head = self.started or false,
  })
  self.instances = instances
  self.started = true
  self.route = payload.route
  return true
end

moonlight.Session = Session

return moonlight
