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

function Function:number(node)
  local kind = self:expression(node)
  if kind ~= "number" then
    fail(self, node, "a comparison is a truth value; the wasm subset does arithmetic on numbers")
  end
end

function Function:condition(node)
  local kind = self:expression(node)
  if kind == "number" then
    self:emit(OP.drop, OP.i32_const, encode.signed(1))
  end
end

function Function:call(node)
  local target = node.target
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

  if kind == "unary" then
    if node.operator == "-" then
      self:number(node.value)
      self:emit("\x9a")
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
      if node.kind == "call" and node.target and node.target.kind == "name" then
        found.called[node.target.name] = true
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
    power_index = nil,
  }

  local found = walk(declarations, { called = {} })
  for _, declaration in ipairs(declarations) do found.called[declaration.name] = nil end

  local external_names = {}
  for name in pairs(options.externals or {}) do
    if found.called[name] then external_names[#external_names + 1] = name end
  end
  table.sort(external_names)

  local needs_power = found.power
  if needs_power then
    unit.power_index = builder:import_function("lunar", "pow", { "f64", "f64" }, { "f64" })
  end

  for _, name in ipairs(external_names) do
    local external = options.externals[name]
    local parameters = {}
    for index = 1, external.arity do parameters[index] = "f64" end
    unit.externals[name] = {
      arity = external.arity,
      index = builder:import_function(external.part or "lunar", external.name or name,
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

  table.sort(exports)
  local needs, seen = {}, {}
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
    externals = external_names,
    needs = needs,
    host = needs_power and { "pow" } or {},
  }
end

return compile
