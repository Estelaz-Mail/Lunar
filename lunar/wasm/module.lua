local encode = require("lunar.wasm.encode")

local module = {}

local Module = {}
Module.__index = Module

function module.new()
  return setmetatable({
    types = {}, type_keys = {},
    imports = {}, functions = {}, exports = {}, elements = {}, segments = {},
    imported_functions = 0,
    memory_limits = nil, imported_memory = false,
    table_limits = nil, imported_table = false,
    closed = false,
  }, Module)
end

local function type_key(parameters, results)
  return table.concat(parameters, ",") .. "->" .. table.concat(results, ",")
end

function Module:type(parameters, results)
  local key = type_key(parameters, results)
  local found = self.type_keys[key]
  if found then return found end
  self.types[#self.types + 1] = encode.function_type(parameters, results)
  self.type_keys[key] = #self.types - 1
  return #self.types - 1
end

local function refuse_late_import(self, what)
  if #self.functions > 0 then
    error("lunar: an imported " .. what .. " has to come before any function of its own", 3)
  end
end

function Module:import_function(namespace, name, parameters, results)
  refuse_late_import(self, "function")
  local index = self:type(parameters, results)
  self.imports[#self.imports + 1] = encode.name(namespace) .. encode.name(name)
    .. "\x00" .. encode.unsigned(index)
  self.imported_functions = self.imported_functions + 1
  return self.imported_functions - 1
end

function Module:import_memory(namespace, name, minimum, maximum)
  refuse_late_import(self, "memory")
  self.imports[#self.imports + 1] = encode.name(namespace) .. encode.name(name)
    .. "\x02" .. encode.limits(minimum or 1, maximum)
  self.imported_memory = true
end

function Module:import_table(namespace, name, minimum, maximum)
  refuse_late_import(self, "table")
  self.imports[#self.imports + 1] = encode.name(namespace) .. encode.name(name)
    .. "\x01" .. encode.value_type("funcref") .. encode.limits(minimum or 0, maximum)
  self.imported_table = true
end

function Module:memory(minimum, maximum)
  self.memory_limits = encode.limits(minimum or 1, maximum)
end

function Module:add_function(parameters, results, locals, body)
  local index = self:type(parameters, results)
  local groups = {}
  for _, group in ipairs(locals or {}) do
    groups[#groups + 1] = encode.unsigned(group.count) .. encode.value_type(group.type)
  end
  local code = encode.vector(groups) .. body .. "\x0b"
  self.functions[#self.functions + 1] = {
    type_index = index,
    code = encode.unsigned(#code) .. code,
  }
  return self.imported_functions + #self.functions - 1
end

function Module:export_function(name, index)
  self.exports[#self.exports + 1] = encode.name(name) .. "\x00" .. encode.unsigned(index)
end

function Module:element(offset, indices)
  local items = {}
  for index, value in ipairs(indices) do items[index] = encode.unsigned(value) end
  self.elements[#self.elements + 1] = "\x00\x41" .. encode.signed(offset) .. "\x0b"
    .. encode.vector(items)
end

function Module:data(offset, bytes)
  self.segments[#self.segments + 1] = "\x00\x41" .. encode.signed(offset) .. "\x0b"
    .. encode.unsigned(#bytes) .. bytes
end

function Module:export_memory(name)
  self.exports[#self.exports + 1] = encode.name(name) .. "\x02" .. encode.unsigned(0)
end

function Module:encode()
  local sections = {}
  local function add(id, payload) sections[#sections + 1] = encode.section(id, payload) end

  add(encode.SECTIONS.type, #self.types > 0 and encode.vector(self.types) or "")
  add(encode.SECTIONS.import, #self.imports > 0 and encode.vector(self.imports) or "")

  local signatures = {}
  local bodies = {}
  for index, entry in ipairs(self.functions) do
    signatures[index] = encode.unsigned(entry.type_index)
    bodies[index] = entry.code
  end
  add(encode.SECTIONS["function"], #signatures > 0 and encode.vector(signatures) or "")

  if self.memory_limits and not self.imported_memory then
    add(encode.SECTIONS.memory, encode.vector({ self.memory_limits }))
  end

  add(encode.SECTIONS.export, #self.exports > 0 and encode.vector(self.exports) or "")
  add(encode.SECTIONS.element, #self.elements > 0 and encode.vector(self.elements) or "")
  add(encode.SECTIONS.code, #bodies > 0 and encode.vector(bodies) or "")
  add(encode.SECTIONS.data, #self.segments > 0 and encode.vector(self.segments) or "")

  return encode.MAGIC .. table.concat(sections)
end

module.Module = Module

return module
