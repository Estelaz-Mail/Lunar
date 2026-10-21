--- Reactivity: signals and effects.
--
-- A signal holds a value and the effects that read it. Reading one inside an
-- effect records the dependency; writing one re-runs every effect that read
-- it. Nothing is declared: the dependency graph is whatever the last run
-- actually touched, which is why a branch that is not taken creates no
-- subscription and an effect that stops reading something stops hearing
-- about it.
--
-- This is the whole reactive core. The component scope turns a plain
-- assignment (`count = count + 1`) into a write here, and the compiler turns
-- every dynamic part of a template into an effect that reads.

local signal = {}

-- The effect currently running, if any. Reads land in its dependency set.
local current = nil
-- Writes made inside a batch run their effects once, at the end.
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

--- Writing the same primitive twice is not a change, so nothing re-runs. A
-- table is always treated as a change: this cannot see inside one, and a
-- component that mutates a list in place would otherwise never update.
function signal.set(self, value)
  local previous = self.value
  if previous == value and type(value) ~= "table" then return value end
  self.value = value
  for effect in pairs(self.subscribers) do schedule(effect) end
  return value
end

--- Forces every effect that reads this signal to re-run, for the case the
-- equality check above cannot see: a value replaced by an equal one that
-- means something different.
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
    -- An effect that throws must not take the rest of the page with it: the
    -- other effects still run, and the message says which one failed.
    io.stderr:write("lunar: effect failed: ", tostring(err), "\n")
    if effect.on_error then effect.on_error(err) end
  end
end

--- Runs `fn` now and again whenever anything it read has changed. Returns a
-- function that stops it.
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

--- Registers work to undo before the running effect runs again, or when it is
-- disposed: an event listener to remove, a timer to cancel.
function signal.on_cleanup(fn)
  if not current then return end
  current.cleanups[#current.cleanups + 1] = fn
end

--- A signal computed from others, recomputed when they change and not before.
function signal.derived(fn)
  local out = signal.new(nil)
  signal.effect(function() signal.set(out, fn()) end)
  return out
end

--- Reads without subscribing, for the value an effect needs but should not
-- re-run for.
function signal.untrack(fn)
  local previous = current
  current = nil
  local ok, value = pcall(fn)
  current = previous
  if not ok then error(value, 0) end
  return value
end

--- Runs `fn`, then runs every effect its writes scheduled, once each.
function signal.batch(fn)
  batch_depth = batch_depth + 1
  local ok, err = pcall(fn)
  batch_depth = batch_depth - 1
  if batch_depth == 0 then flush() end
  if not ok then error(err, 0) end
end

--- Whether an effect is running, which is how the component scope knows a read
-- needs to be tracked at all.
function signal.tracking()
  return current ~= nil
end

signal.Signal = Signal

return signal
