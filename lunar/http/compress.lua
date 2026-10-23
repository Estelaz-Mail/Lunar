local gzip = require("lunar.core.gzip")
local util = require("lunar.core.util")

local compress = {}

local MIN_BYTES = 1024
local MAX_BYTES = 4 * 1024 * 1024
local ENTRIES = 256

local TEXTUAL = {
  "^text/", "^application/javascript", "^application/json", "^application/xml",
  "^application/manifest%+json", "^image/svg%+xml", "%+json$", "%+xml$",
}

local cache = {}
local counted = 0

function compress.accepts(req, wanted)
  local header = req and req:header("accept-encoding")
  if not header then return false end
  for piece in header:gmatch("[^,]+") do
    local token, parameters = piece:match("^%s*([^;%s]+)%s*(.*)$")
    if token == wanted or token == "*" then
      local quality = parameters:match("[qQ]%s*=%s*([%d%.]+)")
      if not quality or tonumber(quality) ~= 0 then return true end
    end
  end
  return false
end

function compress.textual(content_type)
  if type(content_type) ~= "string" then return false end
  local lowered = content_type:lower()
  for _, pattern in ipairs(TEXTUAL) do
    if lowered:find(pattern) then return true end
  end
  return false
end

function compress.sized(length)
  return type(length) == "number" and length >= MIN_BYTES and length <= MAX_BYTES
end

function compress.worth_it(body, content_type)
  if type(body) ~= "string" then return false end
  if not compress.sized(#body) then return false end
  return compress.textual(content_type)
end

function compress.gzip(body)
  local key = util.hash(body) .. "-" .. #body
  local hit = cache[key]
  if hit then return hit end

  local packed = gzip.compress(body)
  if #packed >= #body then packed = false end

  if counted >= ENTRIES then
    cache = {}
    counted = 0
  end
  cache[key] = packed
  counted = counted + 1
  return packed
end

local function header_of(headers, wanted)
  for name, value in pairs(headers or {}) do
    if type(name) == "string" and name:lower() == wanted then return value, name end
  end
  return nil
end

function compress.vary(value)
  if type(value) ~= "string" or value == "" then return "Accept-Encoding" end
  for piece in value:gmatch("[^,]+") do
    local token = piece:match("^%s*(.-)%s*$")
    if token:lower() == "accept-encoding" or token == "*" then return value end
  end
  return value .. ", Accept-Encoding"
end

function compress.response(req, res)
  if type(res) ~= "table" or res.stream or res.file then return res end
  if res.status == 204 or res.status == 304 then return res end
  if header_of(res.headers, "content-encoding") then return res end

  local content_type = header_of(res.headers, "content-type")
  if not compress.worth_it(res.body, content_type) then return res end

  local vary, vary_name = header_of(res.headers, "vary")
  res.headers[vary_name or "Vary"] = compress.vary(vary)
  if not compress.accepts(req, "gzip") then return res end

  local packed = compress.gzip(res.body)
  if not packed then return res end

  res.body = packed
  res.headers["Content-Encoding"] = "gzip"

  local _, length_name = header_of(res.headers, "content-length")
  if length_name then res.headers[length_name] = tostring(#packed) end

  local etag, etag_name = header_of(res.headers, "etag")
  if etag_name and type(etag) == "string" then
    res.headers[etag_name] = (etag:gsub('"$', '-gzip"'))
  end

  return res
end

function compress.forget()
  cache = {}
  counted = 0
end

return compress
