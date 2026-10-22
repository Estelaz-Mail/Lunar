local encode = require("lunar.wasm.encode")
local module_lib = require("lunar.wasm.module")
local parse = require("lunar.wasm.parse")

local compile = {}

local OP = {
  unreachable = "\x00", block = "\x02", loop = "\x03", ["if"] = "\x04",
  ["else"] = "\x05", ["end"] = "\x0b", br = "\x0c", br_if = "\x0d",
  ["return"] = "\x0f", call = "\x10", drop = "\x1a",
  local_get = "\x20", local_set = "\x21", local_tee = "\x22",
  i32_const = "\x41", f64_const = "\x44", i32_eqz = "\x45",
}

local BLOCK = { empty = "\x40", i32 = "\x7f", f64 = "\x7c" }

local COMPARE = {
  ["=="] = "\x61", ["~="] = "\x62", ["<"] = "\x63",
  [">"] = "\x64", ["<="] = "\x65", [">="] = "\x66",
}

local ARITHMETIC = { ["+"] = "\xa0", ["-"] = "\xa1", ["*"] = "\xa2", ["/"] = "\xa3" }

local MATH_OPS = {
  abs = "\x99", floor = "\x9c", ceil = "\x9b", sqrt = "\x9f", trunc = "\x9d",
}

local MATH_PAIRS = { min = "\xa4", max = "\xa5" }

local I32 = {
  trunc_f64_u = "\xfc\x03", wrap_i64 = "\xa7", extend_u = "\xad",
  ["and"] = "\x71", ["or"] = "\x72", xor = "\x73", shl = "\x74", shr_u = "\x76",
  mul = "\x6c", add = "\x6a", sub = "\x6b",
  load8_u = "\x2d\x00\x00", store8 = "\x3a\x00\x00",
}

local F64 = {
  convert_i32_u = "\xb8", convert_i32_s = "\xb7", convert_i64_u = "\xba",
  reinterpret_i64 = "\xbf", load = "\x2b\x03\x00", store = "\x39\x03\x00",
}

local I64 = {
  reinterpret_f64 = "\xbd", const = "\x42",
  ["and"] = "\x83", ["or"] = "\x84", shl = "\x86", shr_u = "\x88",
  eq = "\x51", ne = "\x52",
}

local INTRINSICS = { mem = true, bit = true, box = true }

local BOX_BASE = 0xfff8000000000000
local TAG_MASK = 0x7fff

local TAG = { nothing = 0, boolean = 1, string = 2, table = 3 }

local function boxed(tag, address)
  return string.pack("<I8", BOX_BASE | (tag << 32) | address)
end

local BOX = {
  ["nil"] = boxed(TAG.nothing, 0),
  ["false"] = boxed(TAG.boolean, 0),
  ["true"] = boxed(TAG.boolean, 1),
}

local RUNTIME = {
  concat = 2, length = 1, equal = 2, alloc = 1,
  table_new = 0, table_get = 2, table_set = 3,
}

local Function = {}
Function.__index = Function

local function fail(self, node, message)
  error(string.format("lunar: %s:%d: %s", self.filename, node and node.line or 0, message), 0)
end

function Function:emit(...)
  for _, piece in ipairs({ ... }) do self.body[#self.body + 1] = piece end
end

function Function:local_slot(name)
  for index = #self.scopes, 1, -1 do
    local found = self.scopes[index][name]
    if found then return found end
  end
  return nil
end

function Function:declare(name)
  local slot = self.slots
  self.slots = self.slots + 1
  self.scopes[#self.scopes][name] = slot
  return slot
end

function Function:scratch()
  local slot = self.slots
  self.slots = self.slots + 1
  return slot
end

function Function:push_scope() self.scopes[#self.scopes + 1] = {} end
function Function:pop_scope() self.scopes[#self.scopes] = nil end

function Function:runtime(name)
  local index = self.unit.runtime[name]
  if not index then
    fail(self, nil, "this part cannot reach the runtime's " .. name)
  end
  self:emit(OP.call, encode.unsigned(index))
end

function Function:number(node)
  local kind = self:expression(node)
  if kind == "condition" then
    self:emit(OP["if"], BLOCK.f64, OP.f64_const, BOX["true"],
      OP["else"], OP.f64_const, BOX["false"], OP["end"])
  end
end

function Function:condition(node)
  local kind = self:expression(node)
  if kind == "condition" then return end
  if node.kind == "number" or node.kind == "string" then
    self:emit(OP.drop, OP.i32_const, encode.signed(1))
    return
  end
  if node.kind == "nil" then
    self:emit(OP.drop, OP.i32_const, encode.signed(0))
    return
  end
  local slot = self:scratch()
  self:emit(OP.local_tee, encode.unsigned(slot))
  self:emit(I64.reinterpret_f64, I64.const, encode.signed(BOX_BASE), I64.ne)
  self:emit(OP.local_get, encode.unsigned(slot))
  self:emit(I64.reinterpret_f64, I64.const,
    encode.signed(BOX_BASE | (TAG.boolean << 32)), I64.ne)
  self:emit(I32["and"])
end

function Function:intrinsic(node, namespace, name)
  local arguments = node.arguments
  local function wants(count)
    if #arguments ~= count then
      fail(self, node, string.format("%s.%s takes %d", namespace, name, count))
    end
  end

  self.unit.memory = self.unit.memory or namespace == "mem"

  if namespace == "mem" then
    if name == "load" then
      wants(1)
      self:number(arguments[1])
      self:emit(I32.trunc_f64_u, F64.load)
      return "number"
    end
    if name == "store" then
      wants(2)
      self:number(arguments[1])
      self:emit(I32.trunc_f64_u)
      self:number(arguments[2])
      self:emit(F64.store, OP.f64_const, encode.float(0))
      return "number"
    end
    if name == "byte" then
      wants(1)
      self:number(arguments[1])
      self:emit(I32.trunc_f64_u, I32.load8_u, F64.convert_i32_u)
      return "number"
    end
    if name == "set_byte" then
      wants(2)
      self:number(arguments[1])
      self:emit(I32.trunc_f64_u)
      self:number(arguments[2])
      self:emit(I32.trunc_f64_u, I32.store8, OP.f64_const, encode.float(0))
      return "number"
    end
    if name == "size" then
      wants(0)
      self:emit("\x3f\x00", F64.convert_i32_u)
      return "number"
    end
    if name == "grow" then
      wants(1)
      self:number(arguments[1])
      self:emit(I32.trunc_f64_u, "\x40\x00", F64.convert_i32_s)
      return "number"
    end
    if name == "trap" then
      wants(0)
      self:emit(OP.unreachable, OP.f64_const, encode.float(0))
      return "number"
    end
    fail(self, node, "mem." .. name .. " is not an intrinsic")
  end

  if namespace == "bit" then
    local operation = ({ band = I32["and"], bor = I32["or"], bxor = I32.xor,
      shl = I32.shl, shr = I32.shr_u, mul = I32.mul })[name]
    if not operation then fail(self, node, "bit." .. name .. " is not an intrinsic") end
    wants(2)
    self:number(arguments[1])
    self:emit(I32.trunc_f64_u)
    self:number(arguments[2])
    self:emit(I32.trunc_f64_u, operation, F64.convert_i32_u)
    return "number"
  end

  if namespace == "box" then
    if name == "pack" then
      wants(2)
      self:number(arguments[1])
      self:emit(I32.trunc_f64_u, I32.extend_u, I64.const, encode.signed(32), I64.shl)
      self:number(arguments[2])
      self:emit(I32.trunc_f64_u, I32.extend_u, I64["or"])
      self:emit(I64.const, encode.signed(BOX_BASE), I64["or"], F64.reinterpret_i64)
      return "number"
    end
    if name == "tag" then
      wants(1)
      self:number(arguments[1])
      self:emit(I64.reinterpret_f64, I64.const, encode.signed(32), I64.shr_u)
      self:emit(I64.const, encode.signed(TAG_MASK), I64["and"], F64.convert_i64_u)
      return "number"
    end
    if name == "address" then
      wants(1)
      self:number(arguments[1])
      self:emit(I64.reinterpret_f64, I32.wrap_i64, F64.convert_i32_u)
      return "number"
    end
    if name == "same" then
      wants(2)
      self:number(arguments[1])
      self:emit(I64.reinterpret_f64)
      self:number(arguments[2])
      self:emit(I64.reinterpret_f64, I64.eq)
      return "condition"
    end
    if name == "is_number" then
      wants(1)
      self:number(arguments[1])
      self:emit(I64.reinterpret_f64, I64.const, encode.signed(BOX_BASE), I64["and"])
      self:emit(I64.const, encode.signed(BOX_BASE), I64.ne)
      return "condition"
    end
    fail(self, node, "box." .. name .. " is not an intrinsic")
  end

  fail(self, node, namespace .. "." .. name .. " is not an intrinsic")
end



function Function:call(node)
  local target = node.target
  if target.kind == "field" and target.target.kind == "name"
    and INTRINSICS[target.target.name] then
    return self:intrinsic(node, target.target.name, target.name)
  end

  if target.kind == "field" and target.target.kind == "name"
    and target.target.name == "math" then
    local name = target.name
    local single = MATH_OPS[name]
    if single then
      if #node.arguments ~= 1 then fail(self, node, "math." .. name .. " takes one number") end
      self:number(node.arguments[1])
      self:emit(single)
      return "number"
    end
    local pair = MATH_PAIRS[name]
    if pair then
      if #node.arguments ~= 2 then fail(self, node, "math." .. name .. " takes two numbers") end
      self:number(node.arguments[1])
      self:number(node.arguments[2])
      self:emit(pair)
      return "number"
    end
    fail(self, node, "math." .. name .. " is not part of the wasm subset")
  end

  if target.kind ~= "name" then
    fail(self, node, "the wasm subset calls a name, nothing else")
  end

  local callee = self.unit.functions_by_name[target.name] or self.unit.externals[target.name]
  if not callee then
    fail(self, node, "`" .. target.name .. "` is not a function this part can call")
  end
  if #node.arguments ~= callee.arity then
    fail(self, node, string.format("`%s` takes %d, not %d",
      target.name, callee.arity, #node.arguments))
  end
  for _, argument in ipairs(node.arguments) do self:number(argument) end
  self:emit(OP.call, encode.unsigned(callee.index))
  return "number"
end

function Function:expression(node)
  local kind = node.kind

  if kind == "number" then
    self:emit(OP.f64_const, encode.float(node.value))
    return "number"
  end

  if kind == "string" then
    self:emit(OP.f64_const, self.unit:literal(node.value))
    return "number"
  end

  if kind == "nil" then
    self:emit(OP.f64_const, BOX["nil"])
    return "number"
  end

  if kind == "boolean" then
    self:emit(OP.i32_const, encode.signed(node.value and 1 or 0))
    return "condition"
  end

  if kind == "paren" then
    return self:expression(node.value)
  end

  if kind == "name" then
    local slot = self:local_slot(node.name)
    if not slot then
      fail(self, node, "`" .. node.name .. "` is not a value this part knows")
    end
    self:emit(OP.local_get, encode.unsigned(slot))
    return "number"
  end

  if kind == "call" then
    return self:call(node)
  end

  if kind == "table" then
    local slot = self:scratch()
    self:runtime("table_new")
    self:emit(OP.local_set, encode.unsigned(slot))
    for index, item in ipairs(node.items) do
      self:emit(OP.local_get, encode.unsigned(slot))
      self:emit(OP.f64_const, encode.float(index))
      self:number(item)
      self:runtime("table_set")
      self:emit(OP.drop)
    end
    for _, field in ipairs(node.fields) do
      self:emit(OP.local_get, encode.unsigned(slot))
      self:number(field.key)
      self:number(field.value)
      self:runtime("table_set")
      self:emit(OP.drop)
    end
    self:emit(OP.local_get, encode.unsigned(slot))
    return "number"
  end

  if kind == "index" then
    self:number(node.target)
    self:number(node.key)
    self:runtime("table_get")
    return "number"
  end

  if kind == "field" then
    if node.target.kind == "name" and (INTRINSICS[node.target.name]
      or node.target.name == "math") then
      fail(self, node, node.target.name .. "." .. node.name .. " is something to call, not a value")
    end
    self:number(node.target)
    self:emit(OP.f64_const, self.unit:literal(node.name))
    self:runtime("table_get")
    return "number"
  end

  if kind == "unary" then
    if node.operator == "-" then
      self:number(node.value)
      self:emit("\x9a")
      return "number"
    end
    if node.operator == "#" then
      self:number(node.value)
      self:runtime("length")
      return "number"
    end
    self:condition(node.value)
    self:emit(OP.i32_eqz)
    return "condition"
  end

  if kind == "binary" then
    local operator = node.operator

    if operator == "and" or operator == "or" then
      self:condition(node.left)
      self:emit(OP["if"], BLOCK.i32)
      if operator == "and" then
        self:condition(node.right)
        self:emit(OP["else"], OP.i32_const, encode.signed(0), OP["end"])
      else
        self:emit(OP.i32_const, encode.signed(1), OP["else"])
        self:condition(node.right)
        self:emit(OP["end"])
      end
      return "condition"
    end

    if (operator == "==" or operator == "~=") and self.unit.boxes then
      self:number(node.left)
      self:number(node.right)
      self:runtime("equal")
      self:emit(OP.f64_const, encode.float(0))
      self:emit(operator == "==" and COMPARE["~="] or COMPARE["=="])
      return "condition"
    end

    local comparison = COMPARE[operator]
    if comparison then
      self:number(node.left)
      self:number(node.right)
      self:emit(comparison)
      return "condition"
    end

    local arithmetic = ARITHMETIC[operator]
    if arithmetic then
      self:number(node.left)
      self:number(node.right)
      self:emit(arithmetic)
      return "number"
    end

    if operator == "//" then
      self:number(node.left)
      self:number(node.right)
      self:emit(ARITHMETIC["/"], MATH_OPS.floor)
      return "number"
    end

    if operator == "%" then
      local left, right = self:scratch(), self:scratch()
      self:number(node.left)
      self:emit(OP.local_set, encode.unsigned(left))
      self:number(node.right)
      self:emit(OP.local_set, encode.unsigned(right))
      self:emit(OP.local_get, encode.unsigned(left))
      self:emit(OP.local_get, encode.unsigned(left))
      self:emit(OP.local_get, encode.unsigned(right))
      self:emit(ARITHMETIC["/"], MATH_OPS.floor)
      self:emit(OP.local_get, encode.unsigned(right))
      self:emit(ARITHMETIC["*"], ARITHMETIC["-"])
      return "number"
    end

    if operator == ".." then
      self:number(node.left)
      self:number(node.right)
      self:runtime("concat")
      return "number"
    end

    if operator == "^" then
      self:number(node.left)
      self:number(node.right)
      self:emit(OP.call, encode.unsigned(self.unit.power_index))
      return "number"
    end

    fail(self, node, "`" .. operator .. "` is not part of the wasm subset")
  end

  fail(self, node, "this is not an expression the wasm subset compiles")
end

function Function:statements(list)
  for _, statement in ipairs(list) do self:statement(statement) end
end

function Function:statement(node)
  local kind = node.kind

  if kind == "empty" then return end

  if kind == "local" then
    self:number(node.value)
    self:emit(OP.local_set, encode.unsigned(self:declare(node.name)))
    return
  end

  if kind == "assign" then
    local slot = self:local_slot(node.name)
    if not slot then
      fail(self, node, "`" .. node.name .. "` is not a local of this function")
    end
    self:number(node.value)
    self:emit(OP.local_set, encode.unsigned(slot))
    return
  end

  if kind == "set_index" then
    local target = node.target
    self:number(target.target)
    if target.kind == "field" then
      self:emit(OP.f64_const, self.unit:literal(target.name))
    else
      self:number(target.key)
    end
    self:number(node.value)
    self:runtime("table_set")
    self:emit(OP.drop)
    return
  end

  if kind == "call_statement" then
    self:call(node.value)
    self:emit(OP.drop)
    return
  end

  if kind == "return" then
    if node.value then self:number(node.value)
    else self:emit(OP.f64_const, encode.float(0)) end
    self:emit(OP["return"])
    return
  end

  if kind == "do" then
    self:push_scope()
    self:statements(node.body)
    self:pop_scope()
    return
  end

  if kind == "if" then
    local open = 0
    for index, branch in ipairs(node.branches) do
      if index > 1 then
        self:emit(OP["else"])
        open = open + 1
      end
      self:condition(branch.test)
      self:emit(OP["if"], BLOCK.empty)
      self.depth = self.depth + 1
      self:push_scope()
      self:statements(branch.body)
      self:pop_scope()
    end
    if node.otherwise then
      self:emit(OP["else"])
      self:push_scope()
      self:statements(node.otherwise)
      self:pop_scope()
    end
    for _ = 1, open + 1 do
      self:emit(OP["end"])
      self.depth = self.depth - 1
    end
    return
  end

  if kind == "while" then
    self:emit(OP.block, BLOCK.empty, OP.loop, BLOCK.empty)
    self.depth = self.depth + 2
    local exits = self.exits
    self.exits = self.depth - 1
    self:condition(node.test)
    self:emit(OP.i32_eqz, OP.br_if, encode.unsigned(1))
    self:push_scope()
    self:statements(node.body)
    self:pop_scope()
    self:emit(OP.br, encode.unsigned(0), OP["end"], OP["end"])
    self.depth = self.depth - 2
    self.exits = exits
    return
  end

  if kind == "for" then
    local step = 1.0
    if node.step then
      if node.step.kind ~= "number" then
        fail(self, node, "a wasm `for` wants a step that is a plain number")
      end
      step = node.step.value
    end
    if step == 0 then fail(self, node, "a `for` step of zero never ends") end

    self:push_scope()
    local counter = self:declare(node.name)
    local limit = self:scratch()
    self:number(node.first)
    self:emit(OP.local_set, encode.unsigned(counter))
    self:number(node.last)
    self:emit(OP.local_set, encode.unsigned(limit))

    self:emit(OP.block, BLOCK.empty, OP.loop, BLOCK.empty)
    self.depth = self.depth + 2
    local exits = self.exits
    self.exits = self.depth - 1

    self:emit(OP.local_get, encode.unsigned(counter))
    self:emit(OP.local_get, encode.unsigned(limit))
    self:emit(step > 0 and COMPARE["<="] or COMPARE[">="])
    self:emit(OP.i32_eqz, OP.br_if, encode.unsigned(1))

    self:statements(node.body)

    self:emit(OP.local_get, encode.unsigned(counter))
    self:emit(OP.f64_const, encode.float(step))
    self:emit(ARITHMETIC["+"])
    self:emit(OP.local_set, encode.unsigned(counter))
    self:emit(OP.br, encode.unsigned(0), OP["end"], OP["end"])

    self.depth = self.depth - 2
    self.exits = exits
    self:pop_scope()
    return
  end

  if kind == "break" then
    if not self.exits then fail(self, node, "`break` with no loop around it") end
    self:emit(OP.br, encode.unsigned(self.depth - self.exits))
    return
  end

  fail(self, node, "this statement is not part of the wasm subset")
end

local function compile_function(unit, declaration)
  local self = setmetatable({
    unit = unit, filename = unit.filename, body = {}, scopes = { {} },
    slots = #declaration.parameters, depth = 0, exits = nil,
  }, Function)
  for index, name in ipairs(declaration.parameters) do
    self.scopes[1][name] = index - 1
  end
  self:statements(declaration.body)
  self:emit(OP.f64_const, encode.float(0))
  local extra = self.slots - #declaration.parameters
  local locals = extra > 0 and { { count = extra, type = "f64" } } or {}
  return table.concat(self.body), locals
end

local function walk(nodes, found)
  for _, node in pairs(nodes) do
    if type(node) == "table" then
      if node.kind == "binary" and node.operator == "^" then found.power = true end
      if node.kind == "string" then found.strings = true end
      if node.kind == "unary" and node.operator == "#" then found.strings = true end
      if node.kind == "binary" and node.operator == ".." then found.strings = true end
      if node.kind == "nil" then found.boxes = true end
      if node.kind == "table" or node.kind == "index" or node.kind == "set_index" then
        found.boxes = true
        found.tables = true
      end
      if node.kind == "field" and node.target and node.target.kind == "name"
        and not (INTRINSICS[node.target.name] or node.target.name == "math") then
        found.boxes = true
        found.tables = true
      end
      if node.kind == "binary" and (node.operator == "==" or node.operator == "~=") then
        for _, side in ipairs({ node.left, node.right }) do
          if side.kind == "boolean" or side.kind == "nil" then found.boxes = true end
        end
      end
      if node.kind == "call" and node.target and node.target.kind == "name" then
        found.called[node.target.name] = true
      end
      if node.kind == "call" and node.target and node.target.kind == "field"
        and node.target.target.kind == "name" and INTRINSICS[node.target.target.name] then
        found.memory = found.memory or node.target.target.name == "mem"
      end
      walk(node, found)
    end
  end
  return found
end

function compile.chunk(source, options)
  options = options or {}
  local filename = options.filename or "chunk.lua"
  local declarations = parse.chunk(source, { filename = filename })

  local builder = module_lib.new()
  local unit = {
    filename = filename, functions_by_name = {}, externals = {},
    power_index = nil, runtime = {}, literals = {}, blob = {}, blob_size = 0,
    data_base = options.data_base or 0, boxes = false,
  }

  function unit:literal(value)
    local found = self.literals[value]
    if found then return found end
    local offset = self.data_base + self.blob_size
    local padding = (8 - (#value % 8)) % 8
    self.blob[#self.blob + 1] = string.pack("<d", #value) .. value .. string.rep("\0", padding)
    self.blob_size = self.blob_size + 8 + #value + padding
    local bytes = boxed(TAG.string, offset)
    self.literals[value] = bytes
    return bytes
  end

  local found = walk(declarations, { called = {} })
  for _, declaration in ipairs(declarations) do found.called[declaration.name] = nil end

  local external_names = {}
  for name in pairs(options.externals or {}) do
    if found.called[name] then external_names[#external_names + 1] = name end
  end
  table.sort(external_names)

  unit.boxes = not options.is_runtime and (found.strings or found.boxes) or false

  if found.memory or unit.boxes or options.memory then
    builder:import_memory("host", "memory", 1)
  end

  local needs_power = found.power
  if needs_power then
    unit.power_index = builder:import_function("host", "pow", { "f64", "f64" }, { "f64" })
  end

  local runtime_names = {}
  if unit.boxes then
    for name in pairs(RUNTIME) do
      if name ~= "alloc" then runtime_names[#runtime_names + 1] = name end
    end
    table.sort(runtime_names)
    for _, name in ipairs(runtime_names) do
      local parameters = {}
      for index = 1, RUNTIME[name] do parameters[index] = "f64" end
      unit.runtime[name] = builder:import_function("runtime", name, parameters, { "f64" })
    end
  end

  for _, name in ipairs(external_names) do
    local external = options.externals[name]
    local parameters = {}
    for index = 1, external.arity do parameters[index] = "f64" end
    unit.externals[name] = {
      arity = external.arity,
      index = builder:import_function(external.part or "runtime", external.name or name,
        parameters, { "f64" }),
    }
  end

  local base = builder.imported_functions
  for index, declaration in ipairs(declarations) do
    if unit.functions_by_name[declaration.name] then
      error(string.format("lunar: %s:%d: `%s` is declared twice", filename,
        declaration.line, declaration.name), 0)
    end
    unit.functions_by_name[declaration.name] = {
      arity = #declaration.parameters,
      index = base + index - 1,
      exported = declaration.exported,
    }
  end

  local exports, arities = {}, {}
  for _, declaration in ipairs(declarations) do
    local body, locals = compile_function(unit, declaration)
    local parameters = {}
    for index = 1, #declaration.parameters do parameters[index] = "f64" end
    local index = builder:add_function(parameters, { "f64" }, locals, body)
    if declaration.exported then
      builder:export_function(declaration.name, index)
      exports[#exports + 1] = declaration.name
      arities[declaration.name] = #declaration.parameters
    end
  end

  if unit.blob_size > 0 then
    builder:data(unit.data_base, table.concat(unit.blob))
  end
  for _, segment in ipairs(options.data_segments or {}) do
    builder:data(segment.offset, segment.bytes)
  end

  table.sort(exports)
  local needs, seen = {}, {}
  if unit.boxes then
    seen.runtime = true
    needs[#needs + 1] = "runtime"
  end
  for _, name in ipairs(external_names) do
    local part = options.externals[name].part
    if part and not seen[part] then
      seen[part] = true
      needs[#needs + 1] = part
    end
  end
  table.sort(needs)

  return builder:encode(), {
    exports = exports,
    arities = arities,
    memory = found.memory or unit.boxes or options.memory or false,
    data = table.concat(unit.blob),
    data_size = unit.blob_size,
    externals = external_names,
    needs = needs,
    host = needs_power and { "pow" } or {},
  }
end

return compile
