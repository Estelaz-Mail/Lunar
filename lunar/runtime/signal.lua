local signal = {}

local current = nil
local batch_depth = 0
local pending = {}
local pending_order = {}

local Signal = {}
Signal.__index = Signal

function signal.new(value)
  return setmetatable({ value = value, subscribers = {} }, Signal)
end

function signal.is(value)
  return getmetatable(value) == Signal
end

local function flush()
  while #pending_order > 0 do
    local queue = pending_order
    pending_order = {}
    pending = {}
    for _, effect in ipairs(queue) do
      if not effect.disposed then signal.run(effect) end
    end
  end
end

local function schedule(effect)
  if effect.disposed or effect.running then return end
  if pending[effect] then return end
  pending[effect] = true
  pending_order[#pending_order + 1] = effect
  if batch_depth == 0 then flush() end
end

function signal.get(self)
  if current then
    current.dependencies[self] = true
    self.subscribers[current] = true
  end
  return self.value
end

function signal.set(self, value)
  local previous = self.value
  if previous == value and type(value) ~= "table" then return value end
  self.value = value
  for effect in pairs(self.subscribers) do schedule(effect) end
  return value
end

function signal.invalidate(self)
  for effect in pairs(self.subscribers) do schedule(effect) end
end

local function clear_dependencies(effect)
  for dependency in pairs(effect.dependencies) do
    dependency.subscribers[effect] = nil
  end
  effect.dependencies = {}
end

local function run_cleanups(effect)
  local cleanups = effect.cleanups
  effect.cleanups = {}
  for index = #cleanups, 1, -1 do
    local ok, err = pcall(cleanups[index])
    if not ok then io.stderr:write("lunar: cleanup failed: ", tostring(err), "\n") end
  end
end

function signal.run(effect)
  if effect.disposed then return end
  run_cleanups(effect)
  clear_dependencies(effect)

  local previous = current
  current = effect
  effect.running = true
  local ok, err = pcall(effect.fn)
  effect.running = false
  current = previous

  if not ok then
    io.stderr:write("lunar: effect failed: ", tostring(err), "\n")
    if effect.on_error then effect.on_error(err) end
  end
end

function signal.effect(fn, options)
  local effect = {
    fn = fn,
    dependencies = {},
    cleanups = {},
    disposed = false,
    on_error = options and options.on_error or nil,
  }
  signal.run(effect)
  return function()
    if effect.disposed then return end
    effect.disposed = true
    run_cleanups(effect)
    clear_dependencies(effect)
  end, effect
end

function signal.on_cleanup(fn)
  if not current then return end
  current.cleanups[#current.cleanups + 1] = fn
end

function signal.derived(fn)
  local out = signal.new(nil)
  signal.effect(function() signal.set(out, fn()) end)
  return out
end

function signal.untrack(fn)
  local previous = current
  current = nil
  local ok, value = pcall(fn)
  current = previous
  if not ok then error(value, 0) end
  return value
end

function signal.batch(fn)
  batch_depth = batch_depth + 1
  local ok, err = pcall(fn)
  batch_depth = batch_depth - 1
  if batch_depth == 0 then flush() end
  if not ok then error(err, 0) end
end

function signal.tracking()
  return current ~= nil
end

signal.Signal = Signal

return signal
