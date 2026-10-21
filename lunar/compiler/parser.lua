--- The template parser.
--
-- Markup in, a tree out. The tree is what both code generators walk: the one
-- that writes a string on the server and the one that builds nodes in the
-- browser. Keeping a single tree for both is what makes the two renderings the
-- same page by construction rather than by discipline.
--
-- The syntax, in full. Every expression in it is a Lua expression, checked at
-- compile time, which is why there is no separate expression language here to
-- learn or to get wrong:
--
--   {expr}                     text, escaped
--   {@html expr}               markup, not escaped
--   {#if expr} {:else if expr} {:else} {/if}
--   {#each list as item, index} {:else} {/each}
--   <tag attr="static" attr={expr} attr="mixed {expr}">
--   <tag {name}>               shorthand for name={name}
--   <tag on:click={fn}> <tag on:click|prevent={fn}>
--   <tag class:active={expr}> <tag style:color={expr}>
--   <tag bind:value={target}>
--   <Component prop={expr}>children</Component>
--   <slot />                   where a component's children go
--   <lunar:head>               hoisted into the document head

local html = require("lunar.core.html")
local util = require("lunar.core.util")

local parser = {}

local Parser = {}
Parser.__index = Parser

local BLOCK_OPENERS = { ["if"] = true, each = true }

local function is_component_name(tag)
  return tag:match("^%u") ~= nil
end

function Parser:fail(message, line)
  error(string.format("lunar: %s:%d: %s", self.filename, line or self.line, message), 0)
end

--- Advances past `count` bytes, keeping the line number current.
function Parser:advance(count)
  local chunk = self.source:sub(self.position, self.position + count - 1)
  for _ in chunk:gmatch("\n") do self.line = self.line + 1 end
  self.position = self.position + count
end

function Parser:peek(count)
  return self.source:sub(self.position, self.position + (count or 1) - 1)
end

function Parser:eof()
  return self.position > #self.source
end

--- Reads a `{...}` expression, stopping at the brace that closes the one it
-- started on. Braces inside a string, a long bracket or a comment do not
-- count, which is what lets a template hold `{ { a = 1 } }` or `{ s:find("}") }`.
function Parser:read_braced()
  local start_line = self.line
  if self:peek() ~= "{" then self:fail("expected '{'") end
  self:advance(1)
  local start = self.position
  local depth = 1

  while not self:eof() do
    local char = self:peek()
    if char == "{" then
      depth = depth + 1
      self:advance(1)
    elseif char == "}" then
      depth = depth - 1
      if depth == 0 then
        local code = self.source:sub(start, self.position - 1)
        self:advance(1)
        return code, start_line
      end
      self:advance(1)
    elseif char == '"' or char == "'" then
      self:read_lua_string(char)
    elseif char == "[" and self:peek(2):match("^%[[%[=]") then
      self:read_long_bracket()
    elseif self:peek(2) == "--" then
      self:read_lua_comment()
    else
      self:advance(1)
    end
  end
  self:fail("an expression is never closed", start_line)
end

function Parser:read_lua_string(quote)
  self:advance(1)
  while not self:eof() do
    local char = self:peek()
    if char == "\\" then
      self:advance(2)
    elseif char == quote then
      self:advance(1)
      return
    elseif char == "\n" then
      self:fail("a string in an expression is never closed")
    else
      self:advance(1)
    end
  end
  self:fail("a string in an expression is never closed")
end

function Parser:read_long_bracket()
  local level = self.source:match("^%[(=*)%[", self.position)
  if not level then self:advance(1) return end
  local close = "]" .. level .. "]"
  local stop = self.source:find(close, self.position + #level + 2, true)
  if not stop then self:fail("a long string is never closed") end
  self:advance(stop + #close - self.position)
end

function Parser:read_lua_comment()
  if self.source:match("^%-%-%[=*%[", self.position) then
    self:advance(2)
    self:read_long_bracket()
    return
  end
  local stop = self.source:find("\n", self.position) or (#self.source + 1)
  self:advance(stop - self.position)
end

-- Mustaches -------------------------------------------------------------------

local function expression_error(code, filename, line, what)
  local chunk, message = load("return (" .. code .. "\n)", "=expression")
  if chunk then return end
  error(string.format("lunar: %s:%d: %s is not a Lua expression: %s",
    filename, line, what, tostring(message):gsub("^.-:%d+:%s*", "")), 0)
end

--- Checks an expression at compile time, so a typo is a build error with a
-- line number rather than a page that renders half of itself.
function Parser:check_expression(code, line, what)
  expression_error(code, self.filename, line, what or "an expression")
end

function Parser:parse_mustache(children)
  local code, line = self:read_braced()
  local trimmed = util.trim(code)

  if trimmed == "" then self:fail("an empty expression", line) end

  local marker = trimmed:sub(1, 1)
  if marker == "@" then
    local keyword, rest = trimmed:match("^@(%a+)%s*(.*)$")
    if keyword ~= "html" then
      self:fail("unknown directive {@" .. tostring(keyword) .. "}", line)
    end
    self:check_expression(rest, line, "{@html}")
    children[#children + 1] = { kind = "expr", code = rest, raw = true, line = line }
    return
  end

  if marker == "#" or marker == ":" or marker == "/" then
    return self:parse_block_tag(trimmed, line, children)
  end

  self:check_expression(trimmed, line)
  children[#children + 1] = { kind = "expr", code = trimmed, line = line }
end

--- `{#if}`, `{:else}` and `{/if}` and their `each` counterparts. Blocks live on
-- the same stack as elements so a block closed inside an element, or the other
-- way round, is caught where it happens.
function Parser:parse_block_tag(trimmed, line, children)
  local marker = trimmed:sub(1, 1)
  local body = util.trim(trimmed:sub(2))
  local keyword, rest = body:match("^(%a+)%s*(.*)$")
  keyword = keyword or body

  if marker == "#" then
    if keyword == "await" or keyword == "key" then
      self:fail("{#" .. keyword .. "} is not part of Lunar", line)
    end
    if not BLOCK_OPENERS[keyword] then
      self:fail("unknown block {#" .. tostring(keyword) .. "}", line)
    end
    local node
    if keyword == "if" then
      self:check_expression(rest, line, "{#if}")
      node = { kind = "if", line = line,
        branches = { { test = rest, children = {} } }, else_children = nil }
    else
      node = self:parse_each_head(rest, line)
    end
    children[#children + 1] = node
    self.stack[#self.stack + 1] = { kind = "block", keyword = keyword, node = node, line = line }
    return
  end

  local top = self.stack[#self.stack]
  if marker == ":" then
    if not top or top.kind ~= "block" then
      self:fail("{:" .. body .. "} outside a block", line)
    end
    if keyword == "else" then
      local sub = util.trim(rest)
      if sub:match("^if%f[%s(]") and top.keyword == "if" then
        local test = util.trim(sub:sub(3))
        self:check_expression(test, line, "{:else if}")
        local branch = { test = test, children = {} }
        top.node.branches[#top.node.branches + 1] = branch
        return
      end
      if sub ~= "" then self:fail("{:else " .. sub .. "} makes no sense here", line) end
      top.node.else_children = {}
      return
    end
    self:fail("unknown {:" .. tostring(keyword) .. "}", line)
  end

  -- marker == "/"
  if not top or top.kind ~= "block" then
    self:fail("{/" .. body .. "} with no block open", line)
  end
  if top.keyword ~= keyword then
    self:fail(string.format("{/%s} closes a {#%s} opened on line %d",
      keyword, top.keyword, top.line), line)
  end
  self.stack[#self.stack] = nil
end

--- `list as item`, `list as item, index`. The names become real Lua locals in
-- the generated code, so an expression inside the block sees them by ordinary
-- scoping and not through the component's state.
function Parser:parse_each_head(rest, line)
  if rest:find("%(") and rest:find("%)%s*$") then
    self:fail("a keyed {#each ... (key)} is not part of Lunar: the block "
      .. "re-renders as a whole", line)
  end
  local list, names = rest:match("^(.-)%s+as%s+([%w_%s,]+)$")
  if not list then
    self:fail("{#each} wants `list as item` or `list as item, index`", line)
  end
  local item, index = names:match("^([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*$")
  if not item then
    item = names:match("^([%a_][%w_]*)%s*$")
  end
  if not item then self:fail("{#each}: `" .. util.trim(names) .. "` is not a name", line) end
  self:check_expression(list, line, "{#each}")
  return { kind = "each", list = util.trim(list), item = item, index = index,
    children = {}, else_children = nil, line = line }
end

-- Elements ---------------------------------------------------------------------

local MODIFIERS = { prevent = true, stop = true, once = true, self_ = true,
  capture = true, passive = true, trusted = true }

function Parser:parse_attribute(attributes, tag)
  local source = self.source

  -- `{name}` on its own is `name={name}`; `{...rest}` is a spread.
  if self:peek() == "{" then
    local code, line = self:read_braced()
    local trimmed = util.trim(code)
    local spread = trimmed:match("^%.%.%.%s*(.+)$")
    if spread then
      self:check_expression(spread, line, "a spread attribute")
      attributes[#attributes + 1] = { type = "spread", code = spread, line = line }
      return
    end
    if not trimmed:match("^[%a_][%w_]*$") then
      self:fail("{" .. trimmed .. "} as an attribute wants a plain name", line)
    end
    attributes[#attributes + 1] = { type = "expr", name = trimmed, code = trimmed, line = line }
    return
  end

  local name = source:match("^([%a_@:][%w_%-%.:|]*)", self.position)
  if not name then
    self:fail("cannot read an attribute of <" .. tag .. ">")
  end
  local line = self.line
  self:advance(#name)
  self:skip_space()

  local value_line, raw_value, code
  if self:peek() == "=" then
    self:advance(1)
    self:skip_space()
    local char = self:peek()
    if char == "{" then
      code, value_line = self:read_braced()
      code = util.trim(code)
    elseif char == '"' or char == "'" then
      raw_value, value_line = self:read_quoted(char)
    else
      -- An unquoted value, which HTML allows and this accepts for `type=text`.
      local unquoted = source:match("^[^%s>/]+", self.position)
      if not unquoted then self:fail("an attribute with no value") end
      raw_value = { { kind = "text", value = html.decode(unquoted) } }
      value_line = self.line
      self:advance(#unquoted)
    end
  end

  local directive, argument = name:match("^(%a+):(.+)$")
  if directive == "on" then
    local event, modifiers = self:split_modifiers(argument)
    if not code then self:fail("on:" .. event .. " wants a handler: on:" .. event .. "={fn}", line) end
    self:check_expression(code, value_line, "a handler")
    attributes[#attributes + 1] = { type = "event", name = event, code = code,
      modifiers = modifiers, line = line }
    return
  end
  if directive == "class" or directive == "style" then
    if not code then self:fail(name .. " wants an expression", line) end
    self:check_expression(code, value_line, name)
    attributes[#attributes + 1] = { type = directive, name = argument, code = code, line = line }
    return
  end
  if directive == "bind" then
    if not code then self:fail("bind:" .. argument .. " wants a target", line) end
    self:check_expression(code, value_line, "a binding")
    if not load(code .. " = nil", "=binding") then
      self:fail("bind:" .. argument .. "={" .. code .. "} cannot be assigned to", value_line)
    end
    attributes[#attributes + 1] = { type = "bind", name = argument, code = code, line = line }
    return
  end
  if directive and directive ~= "data" and directive ~= "aria" and name:find(":") then
    -- `xml:lang` and friends are real attribute names; anything else that
    -- looks like a directive and is not one is a typo worth catching.
    if directive ~= "xml" and directive ~= "xlink" and directive ~= "lunar" then
      self:fail("unknown directive " .. name, line)
    end
  end

  if code then
    self:check_expression(code, value_line, name)
    attributes[#attributes + 1] = { type = "expr", name = name, code = code, line = line }
  elseif raw_value then
    attributes[#attributes + 1] = { type = "parts", name = name, parts = raw_value, line = line }
  else
    attributes[#attributes + 1] = { type = "boolean", name = name, line = line }
  end
end

function Parser:split_modifiers(argument)
  local pieces = util.split(argument, "|")
  local event = pieces[1]
  local modifiers = {}
  for index = 2, #pieces do
    local modifier = pieces[index]
    local key = modifier == "self" and "self_" or modifier
    if not MODIFIERS[key] then
      self:fail("unknown event modifier |" .. modifier)
    end
    modifiers[#modifiers + 1] = key
  end
  return event, modifiers
end

--- A quoted attribute value, which may mix text and expressions.
function Parser:read_quoted(quote)
  local line = self.line
  self:advance(1)
  local parts = {}
  local buffer = {}
  local function flush()
    if #buffer > 0 then
      parts[#parts + 1] = { kind = "text", value = html.decode(table.concat(buffer)) }
      buffer = {}
    end
  end

  while not self:eof() do
    local char = self:peek()
    if char == quote then
      self:advance(1)
      flush()
      return parts, line
    elseif char == "{" then
      flush()
      local code, code_line = self:read_braced()
      code = util.trim(code)
      self:check_expression(code, code_line, "an attribute")
      parts[#parts + 1] = { kind = "expr", code = code, line = code_line }
    else
      buffer[#buffer + 1] = char
      self:advance(1)
    end
  end
  self:fail("an attribute value is never closed", line)
end

function Parser:skip_space()
  local space = self.source:match("^%s*", self.position)
  if #space > 0 then self:advance(#space) end
end

--- Reads the text of an element whose content is not markup, verbatim.
function Parser:read_raw_text(tag)
  local close = self.source:find("</" .. tag .. "%s*>", self.position)
  if not close then self:fail("<" .. tag .. "> is never closed") end
  local text = self.source:sub(self.position, close - 1)
  self:advance(close - self.position)
  local _, stop = self.source:find("^</" .. tag .. "%s*>", self.position)
  self:advance(stop - self.position + 1)
  return text
end

function Parser:parse_element(children)
  local line = self.line
  self:advance(1) -- "<"

  if self:peek(3) == "!--" then
    local stop = self.source:find("-->", self.position, true)
    if not stop then self:fail("a comment is never closed", line) end
    self:advance(stop + 3 - self.position)
    return
  end

  if self:peek() == "/" then
    local tag = self.source:match("^/%s*([%w_%-:%.]*)%s*>", self.position)
    if not tag then self:fail("a malformed closing tag", line) end
    local top = self.stack[#self.stack]
    if not top or top.kind ~= "element" then
      self:fail("</" .. tag .. "> with no element open", line)
    end
    if top.node.tag ~= tag then
      self:fail(string.format("</%s> closes <%s>, opened on line %d",
        tag, top.node.tag, top.line), line)
    end
    local _, stop = self.source:find("^/%s*" .. util.pattern_escape(tag) .. "%s*>", self.position)
    self:advance(stop - self.position + 1)
    self.stack[#self.stack] = nil
    return
  end

  local tag = self.source:match("^([%a][%w_%-%.:]*)", self.position)
  if not tag then
    -- A bare `<` that is not a tag is text, which is what a browser does too.
    children[#children + 1] = { kind = "text", value = "<" }
    return
  end
  self:advance(#tag)

  local attributes = {}
  while true do
    self:skip_space()
    local char = self:peek()
    if char == "" then self:fail("<" .. tag .. "> is never closed", line) end
    if char == ">" then
      self:advance(1)
      break
    end
    if self:peek(2) == "/>" then
      self:advance(2)
      attributes.self_closing = true
      break
    end
    self:parse_attribute(attributes, tag)
  end

  local node
  if tag == "slot" then
    node = { kind = "slot", tag = tag, attributes = attributes, children = {}, line = line }
  elseif tag == "lunar:head" then
    node = { kind = "head", tag = tag, children = {}, line = line }
  elseif tag:find("^lunar:") then
    self:fail("unknown special element <" .. tag .. ">", line)
  elseif is_component_name(tag) then
    node = { kind = "component", tag = tag, attributes = attributes,
      children = {}, line = line }
  else
    node = { kind = "element", tag = tag, attributes = attributes,
      children = {}, line = line }
  end
  children[#children + 1] = node

  local void = html.VOID_ELEMENTS[tag]
  if void and attributes.self_closing == nil then attributes.self_closing = true end
  if void or attributes.self_closing then
    if void and #node.children > 0 then
      self:fail("<" .. tag .. "> cannot have children", line)
    end
    node.self_closing = true
    return
  end

  if html.RAW_TEXT_ELEMENTS[tag] and tag ~= "title" then
    node.children[#node.children + 1] = { kind = "text", value = self:read_raw_text(tag) }
    node.raw_text = true
    return
  end

  self.stack[#self.stack + 1] = { kind = "element", node = node, line = line }
end

--- Where the next child goes: the innermost open element, or the branch of the
-- innermost open block.
function Parser:current_children()
  local top = self.stack[#self.stack]
  if not top then return self.root end
  if top.kind == "element" then return top.node.children end
  local node = top.node
  if node.else_children then return node.else_children end
  if node.kind == "if" then return node.branches[#node.branches].children end
  return node.children
end

function parser.parse(source, options)
  options = options or {}
  local self = setmetatable({
    source = source,
    position = 1,
    line = options.line or 1,
    filename = options.filename or "component.lunar",
    root = {},
    stack = {},
  }, Parser)

  local buffer = {}
  local function flush()
    if #buffer > 0 then
      local children = self:current_children()
      -- Decoded here, once: the generators escape it again on the way out,
      -- each in the form its own renderer needs.
      children[#children + 1] = { kind = "text", value = html.decode(table.concat(buffer)) }
      buffer = {}
    end
  end

  while not self:eof() do
    local char = self:peek()
    if char == "<" then
      flush()
      self:parse_element(self:current_children())
    elseif char == "{" then
      flush()
      self:parse_mustache(self:current_children())
    elseif char == "\\" and (self:peek(2) == "\\{" or self:peek(2) == "\\}") then
      -- An escaped brace is a literal brace, for a template that has to show
      -- the syntax it is written in.
      buffer[#buffer + 1] = self:peek(2):sub(2)
      self:advance(2)
    else
      buffer[#buffer + 1] = char
      self:advance(1)
    end
  end
  flush()

  local top = self.stack[#self.stack]
  if top then
    if top.kind == "element" then
      self:fail("<" .. top.node.tag .. "> is never closed", top.line)
    end
    self:fail("{#" .. top.keyword .. "} is never closed", top.line)
  end

  return self.root
end

parser.is_component_name = is_component_name

return parser
