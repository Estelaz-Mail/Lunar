local compiler = require("lunar.compiler")
local html = require("lunar.core.html")
local json = require("lunar.core.json")
local parser = require("lunar.compiler.parser")
local sfc = require("lunar.compiler.sfc")
local util = require("lunar.core.util")

local format = {}

local BLOCK = {}
for tag in ("address article aside blockquote body caption dd details dialog div dl dt fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup hr html li main menu nav ol p pre section summary table tbody td tfoot th thead tr ul script style lunar:head"):gmatch("%S+") do
  BLOCK[tag] = true
end
local PRESERVE = { pre = true, code = true, textarea = true }
local OPERATORS = {}
for operator in ("= + - * / // % ^ & | ~ << >> .. == ~= < > <= >= and or not"):gmatch("%S+") do
  OPERATORS[operator] = true
end

local function lua_tokens(source)
  local tokens, position, line = {}, 1, 1
  while position <= #source do
    local start = position
    local char = source:sub(start, start)
    local space = source:match("^%s+", start)
    local comment = source:sub(start, start + 1) == "--"
    local first = comment and start + 2 or start
    local level = source:match("^%[(=*)%[", first)
    local kind = "symbol"
    if space then
      position = position + #space
    elseif comment or level then
      kind = comment and "comment" or "string"
      if level then
        local closing = "]" .. level .. "]"
        local stop = assert(source:find(closing, first + #level + 2, true), "unclosed Lua literal")
        position = stop + #closing
      else
        position = source:find("\n", start, true) or (#source + 1)
      end
    elseif char == '"' or char == "'" then
      kind = "string"
      position = start + 1
      while position <= #source do
        local next_char = source:sub(position, position)
        if next_char == "\\" then position = position + 2
        elseif next_char == char then position = position + 1; break
        else position = position + 1 end
      end
    else
      local name = source:match("^[%a_][%w_]*", start)
      local number = source:match("^0[xX]%x*%.?%x*[pP][+-]?%d+", start)
        or source:match("^0[xX]%x+%.?%x*", start)
        or source:match("^%d+%.?%d*[eE][+-]?%d+", start)
        or source:match("^%.%d+[eE][+-]?%d+", start)
        or source:match("^%d+%.?%d*", start)
        or source:match("^%.%d+", start)
      if name then kind, position = "name", start + #name
      elseif number then kind, position = "number", start + #number
      else
        local symbol
        for _, candidate in ipairs({ "...", "//", "<<", ">>", "..", "==", "~=", "<=", ">=", "::" }) do
          if source:sub(start, start + #candidate - 1) == candidate then symbol = candidate; break end
        end
        position = start + (symbol and #symbol or 1)
      end
    end
    local raw = source:sub(start, position - 1)
    if not space then tokens[#tokens + 1] = { raw = raw, kind = kind, line = line } end
    for _ in raw:gmatch("\n") do line = line + 1 end
  end
  return tokens
end

local function lua_signature(source)
  local out = {}
  for _, token in ipairs(lua_tokens(source)) do out[#out + 1] = token.kind .. ":" .. token.raw end
  return table.concat(out, "\0")
end

local function indent(depth, options)
  return string.rep(" ", math.max(0, depth) * options.indent)
end

local function lua_body(source, depth, options)
  local tokens = lua_tokens(source)
  local out, current, level, previous = {}, "", depth, nil
  local function flush()
    if current ~= "" then out[#out + 1] = current; current = "" end
  end
  for _, token in ipairs(tokens) do
    local value = token.raw
    local closing = token.kind ~= "string" and token.kind ~= "comment"
      and (value == "end" or value == "until" or value == "else" or value == "elseif"
        or value == "}" or value == ")" or value == "]")
    if closing then level = math.max(depth, level - 1) end
    local last_line = previous and (previous.line + select(2, previous.raw:gsub("\n", ""))) or 0
    if previous and (token.line > last_line or previous.kind == "comment" and not previous.raw:match("^%-%-%[=*%[")) then
      flush()
      if token.line > last_line + 1 and out[#out] ~= "" then out[#out + 1] = "" end
    end
    if current == "" then current = indent(level, options)
    else
      local left = previous.raw
      local separator = " "
      if value == "," or value == ";" or value == ")" or value == "]" or value == "." or value == ":"
        or left == "(" or left == "[" or left == "." or left == ":" then separator = ""
      elseif value == "(" and previous.kind == "name" and left ~= "if" and left ~= "while"
        and left ~= "for" and left ~= "return" and left ~= "not" then separator = ""
      elseif value == "(" and (left == ")" or left == "]") then separator = ""
      elseif value == "[" and (previous.kind == "name" or left == ")" or left == "]") then separator = ""
      elseif value == "}" and left == "{" then separator = ""
      elseif OPERATORS[value] or OPERATORS[left] then separator = " " end
      current = current .. separator
    end
    current = current .. value
    if token.kind ~= "string" and token.kind ~= "comment" then
      if value == "function" or value == "then" or value == "do" or value == "repeat" or value == "else"
        or value == "{" or value == "(" or value == "[" then level = level + 1 end
    end
    previous = token
  end
  flush()
  local result = table.concat(out, "\n")
  assert(lua_signature(source) == lua_signature(result), "lunar fmt: formatting changed Lua tokens")
  return result
end

local function css_body(source, depth, options)
  local out, buffer, level, position, parentheses = {}, "", depth, 1, 0
  local custom_depth = 0
  local function emit(suffix, declaration)
    local text = buffer:gsub("^%s+", "")
    while text:match("%s$") do
      local backslashes = text:sub(1, -2):match("(\\+)$") or ""
      if #backslashes % 2 == 1 then break end
      text = text:sub(1, -2)
    end
    if declaration then text = text:gsub("^([%w_%-]+)%s*:%s*", "%1: ") end
    if text ~= "" or suffix ~= "" then out[#out + 1] = indent(level, options) .. text .. suffix end
    buffer = ""
  end
  while position <= #source do
    local char = source:sub(position, position)
    if char == "\\" then
      buffer = buffer .. source:sub(position, position + 1)
      position = position + 2
    elseif char == '"' or char == "'" then
      local stop, closed = position + 1, false
      while stop <= #source do
        local next_char = source:sub(stop, stop)
        if next_char == "\\" then stop = stop + 2
        elseif next_char == char then stop = stop + 1; closed = true; break
        else stop = stop + 1 end
      end
      assert(closed, "lunar fmt: a CSS string is never closed")
      buffer = buffer .. source:sub(position, stop - 1)
      position = stop
    elseif source:sub(position, position + 1) == "/*" then
      local stop = source:find("*/", position + 2, true)
      assert(stop, "lunar fmt: a CSS comment is never closed")
      buffer = buffer .. source:sub(position, stop + 1)
      position = stop + 2
    elseif char == "(" or char == "[" then
      parentheses = parentheses + 1; buffer = buffer .. char; position = position + 1
    elseif char == ")" or char == "]" then
      parentheses = math.max(0, parentheses - 1); buffer = buffer .. char; position = position + 1
    elseif parentheses == 0 and (custom_depth > 0 or buffer:match("^%s*%-%-[%w_%-]+%s*:")) then
      if char == "{" then custom_depth = custom_depth + 1 end
      if char == "}" and custom_depth > 0 then custom_depth = custom_depth - 1
      elseif char == "}" then
        emit("", true); level = math.max(depth, level - 1); emit("}", false); position = position + 1; goto continue
      end
      if char == ";" and custom_depth == 0 then emit(";", true)
      else buffer = buffer .. char end
      position = position + 1
    elseif parentheses == 0 and char == "{" then
      emit(" {", false); level = level + 1; position = position + 1
    elseif parentheses == 0 and char == "}" then
      emit("", true); level = math.max(depth, level - 1); emit("}", false); position = position + 1
    elseif parentheses == 0 and char == ";" then
      emit(";", true); position = position + 1
    else buffer = buffer .. char; position = position + 1 end
    ::continue::
  end
  emit("", false)
  return table.concat(out, "\n")
end

local function tree(source, filename)
  local root = { kind = "root", children = {} }
  local stack = { root }
  for _, token in ipairs(parser.tokens(source, { filename = filename })) do
    local top = stack[#stack]
    if token.kind == "close" or token.kind == "endblock" then
      top.close = token
      top.original = source:sub(top.open.start, token.finish)
      stack[#stack] = nil
    elseif token.kind == "branch" then
      top.branches = top.branches or {}
      local branch = { open = token, children = {} }
      top.branches[#top.branches + 1] = branch
      top.active = branch.children
    else
      local node = token
      if token.kind == "open" or token.kind == "block" then
        node = { kind = token.kind, tag = token.tag, open = token, children = {} }
      end
      local children = top.active or top.children
      children[#children + 1] = node
      if token.kind == "block" or token.kind == "open" and not token.self_closing and not token.void then
        stack[#stack + 1] = node
      end
    end
  end
  return root
end

local function header(token, depth, options, force_inline)
  if not token.tag then return token.raw end
  if token.kind == "close" then return "</" .. token.tag .. ">" end
  local attributes = {}
  for _, attribute in ipairs(token.attributes or {}) do
    attributes[#attributes + 1] = attribute:gsub("^([%w_@:|.%-]+)%s*=%s*", "%1=")
  end
  local ending = token.self_closing and " />" or ">"
  local flat = "<" .. token.tag .. (#attributes > 0 and (" " .. table.concat(attributes, " ")) or "") .. ending
  if force_inline or #attributes == 0 or #flat + depth * options.indent <= options.width and not flat:find("\n", 1, true) then
    return flat
  end
  local out = { "<" .. token.tag }
  for _, attribute in ipairs(attributes) do out[#out + 1] = indent(depth + 1, options) .. attribute end
  out[#out + 1] = indent(depth, options) .. (token.self_closing and "/>" or ">")
  return table.concat(out, "\n")
end

local function flat(node, depth, options)
  if PRESERVE[node.tag] and node.original then return node.original end
  if node.kind ~= "open" and node.kind ~= "block" and node.kind ~= "root" then return node.raw end
  local out = { node.open and header(node.open, depth, options) or "" }
  for _, child in ipairs(node.children) do out[#out + 1] = flat(child, depth, options) end
  for _, branch in ipairs(node.branches or {}) do
    out[#out + 1] = branch.open.raw
    for _, child in ipairs(branch.children) do out[#out + 1] = flat(child, depth, options) end
  end
  if node.close then out[#out + 1] = header(node.close, depth, options) end
  return table.concat(out)
end

local function block(node)
  if node.kind == "raw" then return node.tag ~= "textarea" end
  if node.kind == "comment" then return true end
  if node.kind == "open" then return BLOCK[node.tag] == true end
  if node.kind == "block" then
    for _, child in ipairs(node.children) do if block(child) then return true end end
  end
  return false
end

local function multiline(node)
  if PRESERVE[node.tag] then return false end
  local found = false
  for _, child in ipairs(node.children) do
    if child.kind == "expr" or child.kind == "text" and child.raw:find("%S") then return false end
    if block(child) then found = true end
  end
  return node.kind == "root" or found
end

local render_node
local function render_children(children, depth, options)
  local out, group = {}, {}
  local function flush()
    local value = util.trim(table.concat(group))
    if value ~= "" then out[#out + 1] = indent(depth, options) .. value end
    group = {}
  end
  for _, child in ipairs(children) do
    if block(child) then
      flush(); out[#out + 1] = render_node(child, depth, options)
    else group[#group + 1] = flat(child, depth, options) end
  end
  flush()
  return table.concat(out, "\n")
end

render_node = function(node, depth, options)
  if node.kind == "raw" and (node.tag == "script" or node.tag == "style") then
    local body = node.tag == "script" and lua_body(node.content, depth + 1, options)
      or css_body(node.content, depth + 1, options)
    return indent(depth, options) .. header(node, depth, options) .. "\n" .. body
      .. "\n" .. indent(depth, options) .. "</" .. node.tag .. ">"
  end
  if node.kind == "comment" then return indent(depth, options) .. node.raw end
  if not multiline(node) then return indent(depth, options) .. flat(node, depth, options) end
  local out = {}
  if node.open then out[#out + 1] = indent(depth, options) .. header(node.open, depth, options) end
  local body_depth = node.kind == "root" and depth or depth + 1
  local body = render_children(node.children, body_depth, options)
  if body ~= "" then out[#out + 1] = body end
  for _, branch in ipairs(node.branches or {}) do
    out[#out + 1] = indent(depth, options) .. branch.open.raw
    local content = render_children(branch.children, body_depth, options)
    if content ~= "" then out[#out + 1] = content end
  end
  if node.close then out[#out + 1] = indent(depth, options) .. header(node.close, depth, options) end
  return table.concat(out, "\n")
end

local function semantic(nodes, preserve)
  local out = {}
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, field in pairs(value) do if key ~= "line" then result[key] = copy(field) end end
    return result
  end
  for _, node in ipairs(nodes) do
    if node.kind ~= "text" or preserve or node.value:find("%S") then
      local item = copy(node)
      if node.children then item.children = semantic(node.children, preserve or PRESERVE[node.tag]) end
      if node.else_children then item.else_children = semantic(node.else_children, preserve) end
      if node.branches then
        for index, branch in ipairs(node.branches) do item.branches[index].children = semantic(branch.children, preserve) end
      end
      out[#out + 1] = item
    end
  end
  return out
end

local function validate(source, filename)
  local generated = compiler.compile(source, { path = filename })
  local chunk, message = load(generated, "@" .. filename, "t", {})
  if not chunk then error("lunar fmt: " .. tostring(message), 0) end
  local parts = sfc.split(source, filename)
  return parts, parser.parse(parts.template, { filename = filename })
end

function format.source(source, options)
  options = options or {}
  local settings = { indent = options.indent or 2, width = options.width or 100 }
  assert(type(settings.indent) == "number" and settings.indent % 1 == 0 and settings.indent >= 1 and settings.indent <= 8,
    "lunar fmt: indent must be a whole number from 1 to 8")
  assert(type(settings.width) == "number" and settings.width % 1 == 0 and settings.width >= 40 and settings.width <= 240,
    "lunar fmt: width must be a whole number from 40 to 240")
  local filename = options.filename or "component.lunar"
  local before, ast = validate(source, filename)
  local root = tree(source, filename)
  local result = render_node(root, 0, settings)
  if multiline(root) then result = result:gsub("%s+$", "") .. "\n" end
  local after, formatted_ast = validate(result, filename)
  assert(lua_signature(before.script) == lua_signature(after.script), "lunar fmt: formatting changed the script")
  assert(json.encode(semantic(ast, false)) == json.encode(semantic(formatted_ast, false)),
    "lunar fmt: formatting would change template content; file was not modified")
  return result
end

format.lua_tokens = lua_tokens

return format
