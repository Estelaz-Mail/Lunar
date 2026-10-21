--- The environment a component's `<script>` runs in.
--
-- This is the idea the framework turns on. The compiler emits the script as
-- `function(_ENV) ... end`, with `_ENV` bound to one of these, so an
-- undeclared assignment in a component is not a global — it is a signal:
--
--   count = 0           -- component state, reactive
--   local total = 0     -- an ordinary local, invisible to the template
--
-- `count = count + 1` anywhere, in a handler or a callback or three functions
-- down, is a tracked write. Nothing rewrites the author's code to make that
-- happen; it is `_ENV` doing what `_ENV` is for.
--
-- A read that is not state falls through to the real globals, so `print`,
-- `math` and `require` still work and are not state. A component that assigns
-- to a name that is also a global shadows it, for that component, deliberately.

local signal = require("lunar.runtime.signal")

local scope = {}

--- Builds the scope for one instance. `builtins` are the names the component
-- API provides (`props`, `watch`, …); they are readable and cannot be
-- assigned to, because a component that shadowed `props` would be a component
-- whose props silently stopped arriving.
function scope.new(instance, builtins)
  local signals = instance.signals or {}
  instance.signals = signals
  local globals = _G

  local function cell(key)
    local existing = signals[key]
    if existing then return existing end
    local created = signal.new(nil)
    signals[key] = created
    return created
  end

  local proxy = setmetatable({}, {
    __index = function(_, key)
      local builtin = builtins and builtins[key]
      if builtin ~= nil then return builtin end
      local existing = signals[key]
      if existing then return signal.get(existing) end
      local global = globals[key]
      if global ~= nil then return global end
      -- Not state yet and not a global: read it as nil, but subscribe, so a
      -- template that reads a name the script assigns later still updates.
      return signal.get(cell(key))
    end,

    __newindex = function(_, key, value)
      if builtins and builtins[key] ~= nil then
        error(string.format("lunar: `%s` is part of the component API and cannot be assigned to", key), 2)
      end
      signal.set(cell(key), value)
    end,

    -- `pairs(_ENV)` in a component should show its state, not a bare table.
    __pairs = function()
      local keys = {}
      for key in pairs(signals) do keys[#keys + 1] = key end
      local index = 0
      return function()
        index = index + 1
        local key = keys[index]
        if key == nil then return nil end
        return key, signal.get(signals[key])
      end
    end,
  })

  return proxy, signals
end

--- Reads a key without subscribing to it, for the runtime's own bookkeeping.
function scope.peek(instance, key)
  local cell = instance.signals[key]
  if not cell then return nil end
  return cell.value
end

--- Writes without going through the proxy, which is how props arrive: the
-- parent's update must not be a dependency of the parent's own effect.
function scope.put(instance, key, value)
  local cell = instance.signals[key]
  if not cell then
    cell = signal.new(nil)
    instance.signals[key] = cell
  end
  signal.set(cell, value)
end

return scope
