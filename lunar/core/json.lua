--- JSON, for the data a `load` function hands to a page.
--
-- The encoder escapes `<`, `>` and `&` as `\uXXXX`. That is not decoration:
-- the result is embedded in a `<script type="application/json">` in the
-- document, and a string containing `</script>` would otherwise end the
-- element early and turn page data into markup.

local json = {}

--- The sentinel for a JSON null, because a Lua table cannot hold a nil value.
json.null = setmetatable({}, { __tostring = function() return "null" end })

--- Marks a table as an array, so an empty one encodes as `[]` and not `{}`.
function json.array(list)
  return setmetatable(list or {}, json.ARRAY)
end

json.ARRAY = { __lunar_json = "array" }

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
  ["<"] = "\\u003c", [">"] = "\\u003e", ["&"] = "\\u0026",
  -- U+2028 and U+2029 are line terminators to a JavaScript parser but not to
  -- a JSON one, and this string may end up inside a script element.
  ["\u{2028}"] = "\\u2028", ["\u{2029}"] = "\\u2029",
}

local function escape_string(value)
  return (value:gsub('[%c"\\<>&]', function(char)
    return ESCAPES[char] or string.format("\\u%04x", char:byte())
  end):gsub("\u{2028}", "\\u2028"):gsub("\u{2029}", "\\u2029"))
end

local function is_array(value)
  if getmetatable(value) == json.ARRAY then return true end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then return false end
    count = count + 1
  end
  return count == #value
end

local encode_value

local function encode_number(value)
  if value ~= value or value == math.huge or value == -math.huge then
    -- JSON has no way to say these, and silently writing `null` hides a bug.
    error("json: cannot encode " .. tostring(value))
  end
  if math.type(value) == "integer" then return string.format("%d", value) end
  return (string.format("%.14g", value))
end

encode_value = function(value, seen, out)
  local kind = type(value)
  if value == json.null or value == nil then
    out[#out + 1] = "null"
  elseif kind == "boolean" then
    out[#out + 1] = value and "true" or "false"
  elseif kind == "number" then
    out[#out + 1] = encode_number(value)
  elseif kind == "string" then
    out[#out + 1] = '"' .. escape_string(value) .. '"'
  elseif kind == "table" then
    if seen[value] then error("json: a table cannot contain itself") end
    seen[value] = true
    if is_array(value) then
      out[#out + 1] = "["
      for index, item in ipairs(value) do
        if index > 1 then out[#out + 1] = "," end
        encode_value(item, seen, out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local keys = {}
      for key in pairs(value) do keys[#keys + 1] = key end
      -- Sorted, so the same data always produces the same bytes: a page's
      -- serialised data is part of its response, and a response that differs
      -- run to run cannot be cached or compared.
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for index, key in ipairs(keys) do
        if index > 1 then out[#out + 1] = "," end
        out[#out + 1] = '"' .. escape_string(tostring(key)) .. '":'
        encode_value(value[key], seen, out)
      end
      out[#out + 1] = "}"
    end
    seen[value] = nil
  else
    error("json: cannot encode a " .. kind)
  end
  return out
end

function json.encode(value)
  return table.concat(encode_value(value, {}, {}))
end

-- Decoding ------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

function Parser:error(message)
  error(string.format("json: %s at byte %d", message, self.position), 0)
end

function Parser:skip_space()
  local _, stop = self.text:find("^[ \t\r\n]*", self.position)
  self.position = stop + 1
end

function Parser:literal(word, value)
  if self.text:sub(self.position, self.position + #word - 1) == word then
    self.position = self.position + #word
    return value
  end
  self:error("unexpected input")
end

local STRING_ESCAPES = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f",
  n = "\n", r = "\r", t = "\t",
}

function Parser:string()
  self.position = self.position + 1
  local parts = {}
  while true do
    local char = self.text:sub(self.position, self.position)
    if char == "" then self:error("unterminated string") end
    if char == '"' then
      self.position = self.position + 1
      return table.concat(parts)
    end
    if char == "\\" then
      local escape = self.text:sub(self.position + 1, self.position + 1)
      if escape == "u" then
        local hex = self.text:sub(self.position + 2, self.position + 5)
        local code = tonumber(hex, 16)
        if not code then self:error("bad \\u escape") end
        self.position = self.position + 6
        -- A surrogate pair is two escapes; the second one is consumed here so
        -- the pair becomes one character rather than two broken ones.
        if code >= 0xd800 and code <= 0xdbff
          and self.text:sub(self.position, self.position + 1) == "\\u" then
          local low = tonumber(self.text:sub(self.position + 2, self.position + 5), 16)
          if low and low >= 0xdc00 and low <= 0xdfff then
            code = 0x10000 + (code - 0xd800) * 0x400 + (low - 0xdc00)
            self.position = self.position + 6
          end
        end
        parts[#parts + 1] = utf8.char(code)
      else
        local literal = STRING_ESCAPES[escape]
        if not literal then self:error("bad escape") end
        parts[#parts + 1] = literal
        self.position = self.position + 2
      end
    else
      local stop = self.text:find('[\\"]', self.position) or (#self.text + 1)
      parts[#parts + 1] = self.text:sub(self.position, stop - 1)
      self.position = stop
    end
  end
end

function Parser:value()
  self:skip_space()
  local char = self.text:sub(self.position, self.position)
  if char == "" then self:error("unexpected end of input") end
  if char == '"' then return self:string() end
  if char == "{" then
    self.position = self.position + 1
    local out = {}
    self:skip_space()
    if self.text:sub(self.position, self.position) == "}" then
      self.position = self.position + 1
      return out
    end
    while true do
      self:skip_space()
      if self.text:sub(self.position, self.position) ~= '"' then self:error("expected a key") end
      local key = self:string()
      self:skip_space()
      if self.text:sub(self.position, self.position) ~= ":" then self:error("expected ':'") end
      self.position = self.position + 1
      out[key] = self:value()
      self:skip_space()
      local next_char = self.text:sub(self.position, self.position)
      self.position = self.position + 1
      if next_char == "}" then return out end
      if next_char ~= "," then self:error("expected ',' or '}'") end
    end
  end
  if char == "[" then
    self.position = self.position + 1
    local out = {}
    self:skip_space()
    if self.text:sub(self.position, self.position) == "]" then
      self.position = self.position + 1
      return json.array(out)
    end
    while true do
      out[#out + 1] = self:value()
      self:skip_space()
      local next_char = self.text:sub(self.position, self.position)
      self.position = self.position + 1
      if next_char == "]" then return out end
      if next_char ~= "," then self:error("expected ',' or ']'") end
    end
  end
  if char == "t" then return self:literal("true", true) end
  if char == "f" then return self:literal("false", false) end
  if char == "n" then return self:literal("null", json.null) end

  local number = self.text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", self.position)
  if number and tonumber(number) then
    self.position = self.position + #number
    return tonumber(number)
  end
  self:error("unexpected input")
end

--- Returns the value, or nil and a message. A caller parsing a request body
-- should never have to wrap this in `pcall` itself.
function json.decode(text)
  if type(text) ~= "string" then return nil, "json: not a string" end
  local parser = setmetatable({ text = text, position = 1 }, Parser)
  local ok, value = pcall(function()
    local result = parser:value()
    parser:skip_space()
    if parser.position <= #parser.text then parser:error("trailing input") end
    return result
  end)
  if not ok then return nil, value end
  return value
end

return json
