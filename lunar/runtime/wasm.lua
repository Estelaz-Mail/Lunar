local json = require("lunar.core.json")

local wasm = {}

local Loader = {}
Loader.__index = Loader

local function chain(promise, on_resolved, on_rejected)
  local next_promise = promise["then"](promise, on_resolved)
  if on_rejected then return next_promise["catch"](next_promise, on_rejected) end
  return next_promise
end

function wasm.browser(window, js, options)
  options = options or {}
  return setmetatable({
    window = window,
    js = js,
    base = options.base or "/_lunar/wasm/",
    index = nil,
    instances = {},
    waiting = {},
    failed = {},
  }, Loader)
end

function Loader:host_imports()
  local object = self.js.new(self.window.Object)
  object.pow = self.window.Math.pow
  object.memory = self:memory()
  object.table = self:table()
  return object
end

function Loader:table()
  if not self.functions then
    local descriptor = self.js.new(self.window.Object)
    descriptor.element = "anyfunc"
    descriptor.initial = (self.index and self.index.table_size or 0) + 1
    self.functions = self.js.new(self.window.WebAssembly.Table, descriptor)
  end
  return self.functions
end

function Loader:memory()
  if not self.shared then
    self.shared = self.js.new(self.window.WebAssembly.Memory,
      (function()
        local descriptor = self.js.new(self.window.Object)
        descriptor.initial = 2
        return descriptor
      end)())
  end
  return self.shared
end

function Loader:import_object(part)
  local imports = self.js.new(self.window.Object)
  imports.host = self:host_imports()
  for _, needed in ipairs(part.needs or {}) do
    local instance = self.instances[needed]
    if not instance then return nil, needed .. " is not loaded yet" end
    imports[needed] = instance.exports
  end
  return imports
end

function Loader:read_index(on_ready, on_error)
  if self.index then return on_ready(self.index) end
  if self.index_error then return on_error(self.index_error) end

  local queue = self.waiting.index
  if queue then
    queue[#queue + 1] = { ready = on_ready, failed = on_error }
    return
  end
  self.waiting.index = { { ready = on_ready, failed = on_error } }

  local function settle(index, message)
    local pending = self.waiting.index or {}
    self.waiting.index = nil
    self.index = index
    self.index_error = message
    for _, listener in ipairs(pending) do
      if index then listener.ready(index) else listener.failed(message) end
    end
  end

  chain(chain(self.window:fetch(self.base .. "index.json"), function(res)
    if not res.ok then
      settle(nil, "the wasm index answered " .. tostring(res.status))
      return nil
    end
    return res:text()
  end), function(text)
    if text == nil then return end
    local decoded = json.decode(text)
    if type(decoded) ~= "table" or type(decoded.parts) ~= "table" then
      return settle(nil, "the wasm index is not what this expects")
    end
    settle(decoded)
  end, function(err)
    settle(nil, tostring(err))
  end)
end

function Loader:instantiate(index, name, on_ready, on_error)
  local existing = self.instances[name]
  if existing then return on_ready(existing) end

  local part = index.parts[name]
  if not part then return on_error("there is no wasm part called " .. tostring(name)) end

  local queue = self.waiting[name]
  if queue then
    queue[#queue + 1] = { ready = on_ready, failed = on_error }
    return
  end
  self.waiting[name] = { { ready = on_ready, failed = on_error } }

  local function settle(instance, message)
    local pending = self.waiting[name] or {}
    self.waiting[name] = nil
    if instance then self.instances[name] = instance end
    for _, listener in ipairs(pending) do
      if instance then listener.ready(instance) else listener.failed(message) end
    end
  end

  local function build()
    local imports, missing = self:import_object(part)
    if not imports then return settle(nil, missing) end
    local url = self.base .. name .. ".wasm?v=" .. tostring(part.digest or "0")
    chain(chain(chain(self.window:fetch(url), function(res)
      if not res.ok then
        settle(nil, name .. ".wasm answered " .. tostring(res.status))
        return nil
      end
      return res:arrayBuffer()
    end), function(buffer)
      if buffer == nil then return nil end
      return self.window.WebAssembly:instantiate(buffer, imports)
    end), function(result)
      if result == nil then return end
      settle(result.instance)
    end, function(err)
      settle(nil, tostring(err))
    end)
  end

  local pending = {}
  for _, needed in ipairs(part.needs or {}) do
    if not self.instances[needed] then pending[#pending + 1] = needed end
  end

  local function next_dependency()
    local needed = table.remove(pending, 1)
    if not needed then return build() end
    self:instantiate(index, needed, function() next_dependency() end, function(message)
      settle(nil, message)
    end)
  end

  next_dependency()
end

function Loader:load(name, on_ready, on_error)
  on_error = on_error or function(message)
    self.window.console:warn("lunar: wasm: " .. tostring(message))
  end

  self:read_index(function(index)
    local part_name = index.index and index.index[name]
    if not part_name then
      return on_error("no wasm part exports `" .. tostring(name) .. "`")
    end
    self:instantiate(index, part_name, function(instance)
      local exported = instance.exports[name]
      if not exported then
        return on_error("`" .. tostring(name) .. "` is missing from " .. part_name)
      end
      on_ready(function(...) return self:decode(exported(...)) end)
    end, on_error)
  end, on_error)
end

local BOX_BASE = 0xfff8000000000000
local TAG_MASK = 0x7fff

function Loader:bytes()
  local memory = self:memory()
  local buffer = memory.buffer
  if self.view == nil or self.view_of ~= buffer then
    self.view = self.js.new(self.window.Uint8Array, buffer)
    self.view_of = buffer
  end
  return self.view
end

function Loader:decode(value)
  if type(value) ~= "number" then return value end
  local bits = string.unpack("<I8", string.pack("<d", value))
  if bits & BOX_BASE ~= BOX_BASE then return value end

  local tag = (bits >> 32) & TAG_MASK
  local address = bits & 0xffffffff
  if tag == 0 then return nil end
  if tag == 1 then return address == 1 end
  if tag ~= 2 then return value end

  local bytes = self:bytes()
  local header = {}
  for index = 0, 7 do header[index + 1] = string.char(bytes[address + index]) end
  local size = math.tointeger(string.unpack("<d", table.concat(header))) or 0

  local out = {}
  for index = 1, size do
    out[index] = string.char(bytes[address + 7 + index])
  end
  return table.concat(out)
end

function Loader:loaded(name)
  return self.instances[name] ~= nil
end

return wasm
