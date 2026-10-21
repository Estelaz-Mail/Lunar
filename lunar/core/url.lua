--- URLs, as much of them as a server needs.
--
-- Percent-decoding, the query string, and the path split into segments. There
-- is no URL building here: a framework that builds URLs for you is a framework
-- that has opinions about your routes.

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

--- Percent-encodes a path, leaving the separators alone, so a redirect built
-- from a decoded path cannot smuggle anything into the header.
function url.encode_path(path)
  return (path:gsub("[^%w%-%.%_%~/]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

--- `a=1&b=2` as a table. A repeated key becomes a list, because a form with
-- two checkboxes of the same name is a real form.
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

--- Splits a request target into the parts a router needs. The path is
-- decoded; the raw form is kept because that is what a redirect has to echo.
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

--- The segments of a path, decoded. `/blog/a%20b/` is two segments.
function url.segments(path)
  local out = {}
  for segment in path:gmatch("[^/]+") do out[#out + 1] = url.decode(segment) end
  return out
end

--- Normalises a path: collapses `//`, resolves `.` and `..`, and never lets
-- the result climb above the root. This is what a static file handler is
-- built on, so it is the one function here that has to be right.
function url.normalize(path)
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    if segment == "." then
      -- nothing
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
