local parse = {}

local KEYWORDS = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["if"] = true, ["local"] = true, ["nil"] = true,
  ["not"] = true, ["or"] = true, ["return"] = true, ["then"] = true,
  ["true"] = true, ["while"] = true,
}

local SYMBOLS = {
  "...", "//", "==", "~=", "<=", ">=", "..",
  "+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")", "{", "}",
  "[", "]", ";", ":", ",", ".",
}

local Lexer = {}
Lexer.__index = Lexer

local function fail(filename, line, message)
  error(string.format("lunar: %s:%d: %s", filename, line, message), 0)
end

function Lexer:error(message, line)
  fail(self.filename, line or self.line, message)
end

function Lexer:next_token()
  local source = self.source
  while true do
    local space = source:match("^%s*", self.position)
    for _ in space:gmatch("\n") do self.line = self.line + 1 end
    self.position = self.position + #space
    local comment = source:match("^%-%-[^\n]*", self.position)
    if not comment then break end
    self.position = self.position + #comment
  end

  if self.position > #source then
    return { kind = "eof", line = self.line }
  end

  local line = self.line
  local name = source:match("^[%a_][%w_]*", self.position)
  if name then
    self.position = self.position + #name
    if KEYWORDS[name] then return { kind = name, value = name, line = line } end
    return { kind = "name", value = name, line = line }
  end

  local number = source:match("^0[xX]%x+", self.position)
    or source:match("^%d+%.?%d*[eE][-+]?%d+", self.position)
    or source:match("^%d*%.%d+", self.position)
    or source:match("^%d+%.?", self.position)
  if number then
    local value = tonumber(number)
    if not value then self:error("`" .. number .. "` is not a number", line) end
    self.position = self.position + #number
    return { kind = "number", value = value + 0.0, line = line }
  end

  for _, symbol in ipairs(SYMBOLS) do
    if source:sub(self.position, self.position + #symbol - 1) == symbol then
      self.position = self.position + #symbol
      return { kind = symbol, value = symbol, line = line }
    end
  end

  self:error("`" .. source:sub(self.position, self.position) .. "` has no place here", line)
end

local Parser = {}
Parser.__index = Parser

function Parser:error(message, line)
  fail(self.filename, line or self.token.line, message)
end

function Parser:advance()
  self.token = self.lexer:next_token()
  return self.token
end

function Parser:check(kind)
  return self.token.kind == kind
end

function Parser:accept(kind)
  if self.token.kind ~= kind then return nil end
  local token = self.token
  self:advance()
  return token
end

function Parser:expect(kind, what)
  local token = self:accept(kind)
  if not token then
    self:error(string.format("expected %s, found `%s`", what or ("`" .. kind .. "`"),
      tostring(self.token.value or self.token.kind)))
  end
  return token
end

local BINARY = {
  ["or"] = { 1, 1 }, ["and"] = { 2, 2 },
  ["<"] = { 3, 3 }, [">"] = { 3, 3 }, ["<="] = { 3, 3 },
  [">="] = { 3, 3 }, ["~="] = { 3, 3 }, ["=="] = { 3, 3 },
  [".."] = { 5, 4 },
  ["+"] = { 6, 6 }, ["-"] = { 6, 6 },
  ["*"] = { 7, 7 }, ["/"] = { 7, 7 }, ["//"] = { 7, 7 }, ["%"] = { 7, 7 },
  ["^"] = { 10, 9 },
}

local UNARY = 8

function Parser:primary()
  local token = self.token
  if self:accept("(") then
    local inner = self:expression(0)
    self:expect(")")
    return { kind = "paren", value = inner, line = token.line }
  end
  if token.kind == "number" then
    self:advance()
    return { kind = "number", value = token.value, line = token.line }
  end
  if token.kind == "true" or token.kind == "false" then
    self:advance()
    return { kind = "boolean", value = token.kind == "true", line = token.line }
  end
  if token.kind == "name" then
    self:advance()
    local node = { kind = "name", name = token.value, line = token.line }
    while true do
      if self:accept(".") then
        local field = self:expect("name", "a field name")
        node = { kind = "field", target = node, name = field.value, line = field.line }
      elseif self:check("(") then
        node = { kind = "call", target = node, arguments = self:arguments(), line = token.line }
      else
        return node
      end
    end
  end
  self:error("`" .. tostring(token.value or token.kind) .. "` is not an expression")
end

function Parser:arguments()
  self:expect("(")
  local arguments = {}
  if not self:check(")") then
    repeat
      arguments[#arguments + 1] = self:expression(0)
    until not self:accept(",")
  end
  self:expect(")")
  return arguments
end

function Parser:expression(limit)
  local left
  local token = self.token
  if self:accept("-") then
    left = { kind = "unary", operator = "-", value = self:expression(UNARY), line = token.line }
  elseif self:accept("not") then
    left = { kind = "unary", operator = "not", value = self:expression(UNARY), line = token.line }
  else
    left = self:primary()
  end

  while true do
    local operator = self.token.kind
    local priority = BINARY[operator]
    if not priority or priority[1] <= limit then return left end
    local line = self.token.line
    self:advance()
    local right = self:expression(priority[2])
    left = { kind = "binary", operator = operator, left = left, right = right, line = line }
  end
end

function Parser:block(stop)
  local statements = {}
  while true do
    local kind = self.token.kind
    if kind == "eof" or stop[kind] then return statements end
    statements[#statements + 1] = self:statement()
  end
end

function Parser:statement()
  local token = self.token

  if self:accept(";") then return { kind = "empty", line = token.line } end

  if self:accept("local") then
    if self:check("function") then
      self:error("a nested `local function` is not part of the wasm subset", token.line)
    end
    local name = self:expect("name", "a name")
    self:expect("=", "`=`: a local in the wasm subset is always given a value")
    local value = self:expression(0)
    return { kind = "local", name = name.value, value = value, line = token.line }
  end

  if self:accept("if") then
    local node = { kind = "if", branches = {}, line = token.line }
    local test = self:expression(0)
    self:expect("then")
    node.branches[1] = { test = test, body = self:block({ ["elseif"] = true,
      ["else"] = true, ["end"] = true }) }
    while self:accept("elseif") do
      local next_test = self:expression(0)
      self:expect("then")
      node.branches[#node.branches + 1] = { test = next_test,
        body = self:block({ ["elseif"] = true, ["else"] = true, ["end"] = true }) }
    end
    if self:accept("else") then
      node.otherwise = self:block({ ["end"] = true })
    end
    self:expect("end")
    return node
  end

  if self:accept("while") then
    local test = self:expression(0)
    self:expect("do")
    local body = self:block({ ["end"] = true })
    self:expect("end")
    return { kind = "while", test = test, body = body, line = token.line }
  end

  if self:accept("for") then
    local name = self:expect("name", "a loop variable")
    self:expect("=", "`=`: only a numeric `for` is part of the wasm subset")
    local first = self:expression(0)
    self:expect(",")
    local last = self:expression(0)
    local step
    if self:accept(",") then step = self:expression(0) end
    self:expect("do")
    local body = self:block({ ["end"] = true })
    self:expect("end")
    return { kind = "for", name = name.value, first = first, last = last, step = step,
      body = body, line = token.line }
  end

  if self:accept("do") then
    local body = self:block({ ["end"] = true })
    self:expect("end")
    return { kind = "do", body = body, line = token.line }
  end

  if self:accept("break") then
    return { kind = "break", line = token.line }
  end

  if self:accept("return") then
    local value
    if not (self:check("end") or self:check("eof") or self:check(";")) then
      value = self:expression(0)
    end
    self:accept(";")
    return { kind = "return", value = value, line = token.line }
  end

  local target = self:primary()
  if target.kind == "call" then
    return { kind = "call_statement", value = target, line = token.line }
  end
  if target.kind ~= "name" then
    self:error("this cannot be assigned to", token.line)
  end
  self:expect("=", "`=`")
  return { kind = "assign", name = target.name, value = self:expression(0), line = token.line }
end

function Parser:chunk()
  local functions = {}
  while not self:check("eof") do
    local exported = true
    local line = self.token.line
    if self:accept("local") then exported = false end
    self:expect("function", "a function declaration")
    local name = self:expect("name", "a function name")
    self:expect("(")
    local parameters = {}
    if not self:check(")") then
      repeat
        parameters[#parameters + 1] = self:expect("name", "a parameter name").value
      until not self:accept(",")
    end
    self:expect(")")
    local body = self:block({ ["end"] = true })
    self:expect("end")
    functions[#functions + 1] = { name = name.value, parameters = parameters,
      body = body, exported = exported, line = line }
  end
  return functions
end

function parse.chunk(source, options)
  options = options or {}
  local filename = options.filename or "chunk.lua"
  local lexer = setmetatable({ source = source, position = 1, line = options.line or 1,
    filename = filename }, Lexer)
  local self = setmetatable({ lexer = lexer, filename = filename }, Parser)
  self:advance()
  return self:chunk()
end

return parse
