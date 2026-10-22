local util = {}

function util.trim(value)
  return (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))
end

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

function util.count_lines(value)
  local lines = 1
  for _ in value:gmatch("\n") do lines = lines + 1 end
  return lines
end

function util.hash(value)
  local hash = 2166136261
  for index = 1, #value do
    hash = hash ~ value:byte(index)
    hash = (hash * 16777619) & 0xffffffff
  end
  return string.format("%08x", hash)
end

return util
