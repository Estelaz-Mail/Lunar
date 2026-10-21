--- The handful of string and table helpers everything else here uses.
--
-- Lua's standard library stops at `string.gsub`, and a framework that reaches
-- for a utility library is a framework with a dependency. These are the ones
-- that earn their place by being used in three files or more.

local util = {}

function util.trim(value)
  return (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Escapes the magic characters of a Lua pattern, for the many places a
-- literal has to be used where a pattern is expected.
function util.pattern_escape(value)
  return (value:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

function util.starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

function util.ends_with(value, suffix)
  return suffix == "" or value:sub(-#suffix) == suffix
end

function util.split(value, separator)
  local out = {}
  local pattern = "([^" .. util.pattern_escape(separator) .. "]*)"
  for piece in value:gmatch(pattern .. util.pattern_escape(separator) .. "?") do
    out[#out + 1] = piece
  end
  -- A trailing empty capture is dropped, so `split("a/b", "/")` is two
  -- segments, `split("a/b/", "/")` is the same two, and `split("", "/")` is
  -- none. An empty segment *between* separators is kept, because `a//b` is
  -- not `a/b`.
  if #out > 0 and out[#out] == "" and not util.ends_with(value, separator) then
    out[#out] = nil
  end
  return out
end

function util.map(list, fn)
  local out = {}
  for index, item in ipairs(list) do out[index] = fn(item, index) end
  return out
end

function util.filter(list, fn)
  local out = {}
  for index, item in ipairs(list) do
    if fn(item, index) then out[#out + 1] = item end
  end
  return out
end

function util.includes(list, needle)
  for _, item in ipairs(list) do
    if item == needle then return true end
  end
  return false
end

function util.keys(map)
  local out = {}
  for key in pairs(map) do out[#out + 1] = key end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

--- A shallow merge, left to right, for option tables.
function util.merge(...)
  local out = {}
  for index = 1, select("#", ...) do
    local source = select(index, ...)
    if source then
      for key, value in pairs(source) do out[key] = value end
    end
  end
  return out
end

function util.read_file(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local contents = handle:read("a")
  handle:close()
  return contents
end

function util.write_file(path, contents)
  local handle = io.open(path, "wb")
  if not handle then return false end
  handle:write(contents)
  handle:close()
  return true
end

function util.file_exists(path)
  local handle = io.open(path, "rb")
  if not handle then return false end
  handle:close()
  return true
end

--- How many lines a chunk of source occupies, which the compiler needs to keep
-- the generated module's line numbers on top of the component's.
function util.count_lines(value)
  local lines = 1
  for _ in value:gmatch("\n") do lines = lines + 1 end
  return lines
end

--- FNV-1a, 32 bits, as the short stable hash the CSS scoping class and the
-- moonlight bundle's cache key are built from. It is not a security primitive and
-- is not used as one.
function util.hash(value)
  local hash = 2166136261
  for index = 1, #value do
    hash = hash ~ value:byte(index)
    hash = (hash * 16777619) & 0xffffffff
  end
  return string.format("%08x", hash)
end

return util
