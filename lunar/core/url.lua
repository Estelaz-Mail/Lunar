local util = require("lunar.core.util")

local url = {}

function url.decode(value)
  if value == nil then return nil end
  return (value:gsub("+", " "):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function url.encode(value)
  return (tostring(value):gsub("[^%w%-%.%_%~]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

function url.encode_path(path)
  return (path:gsub("[^%w%-%.%_%~/]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

function url.parse_query(search)
  local out = {}
  if search == nil or search == "" then return out end
  if search:sub(1, 1) == "?" then search = search:sub(2) end
  for pair in search:gmatch("[^&;]+") do
    local key, value = pair:match("^([^=]*)=?(.*)$")
    key = url.decode(key)
    value = url.decode(value)
    if key ~= "" then
      local existing = out[key]
      if existing == nil then
        out[key] = value
      elseif type(existing) == "table" then
        existing[#existing + 1] = value
      else
        out[key] = { existing, value }
      end
    end
  end
  return out
end

function url.parse(target)
  local raw_path, search, hash = target:match("^([^?#]*)%??([^#]*)#?(.*)$")
  raw_path = raw_path ~= "" and raw_path or "/"
  return {
    raw_path = raw_path,
    path = url.decode(raw_path),
    search = search ~= "" and ("?" .. search) or "",
    query = url.parse_query(search),
    hash = hash ~= "" and ("#" .. hash) or "",
  }
end

function url.segments(path)
  local out = {}
  for segment in path:gmatch("[^/]+") do out[#out + 1] = url.decode(segment) end
  return out
end

function url.normalize(path)
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    if segment == "." then
    elseif segment == ".." then
      segments[#segments] = nil
    else
      segments[#segments + 1] = segment
    end
  end
  return "/" .. table.concat(segments, "/")
end

url.trim = util.trim

return url
