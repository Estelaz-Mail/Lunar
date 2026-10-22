local signal = require("lunar.runtime.signal")

local scope = {}

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
      return signal.get(cell(key))
    end,

    __newindex = function(_, key, value)
      if builtins and builtins[key] ~= nil then
        error(string.format("lunar: `%s` is part of the component API and cannot be assigned to", key), 2)
      end
      signal.set(cell(key), value)
    end,

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

function scope.peek(instance, key)
  local cell = instance.signals[key]
  if not cell then return nil end
  return cell.value
end

function scope.put(instance, key, value)
  local cell = instance.signals[key]
  if not cell then
    cell = signal.new(nil)
    instance.signals[key] = cell
  end
  signal.set(cell, value)
end

return scope
