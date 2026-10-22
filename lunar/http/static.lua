local mime = require("lunar.core.mime")
local response = require("lunar.http.response")
local url = require("lunar.core.url")
local util = require("lunar.core.util")

local static = {}

local Static = {}
Static.__index = Static

function static.new(options)
  options = options or {}
  return setmetatable({
    root = (options.root or "static"):gsub("/+$", ""),
    version = tostring(options.version or "0"),
    cache_control = options.cache_control or "public, max-age=3600",
    immutable_patterns = options.immutable_patterns or {},
  }, Static)
end

function Static:resolve(path)
  local decoded = url.decode(path or "/")
  if decoded:find("%z") then return nil end
  local normalized = url.normalize(decoded)
  if normalized == "/" or normalized:find("/%.%.") then return nil end
  for segment in normalized:gmatch("[^/]+") do
    if segment:sub(1, 1) == "." then return nil end
  end
  return self.root .. normalized, normalized:sub(2)
end

local function file_length(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local length = handle:seek("end")
  handle:close()
  return length
end

function Static:cache_header(relative)
  for _, pattern in ipairs(self.immutable_patterns) do
    if relative:match(pattern) then
      return "public, max-age=31536000, immutable"
    end
  end
  return self.cache_control
end

function Static:serve(req, path)
  local absolute, relative = self:resolve(path or req.path)
  if not absolute then return nil end

  local length = file_length(absolute)
  if not length then return nil end

  local etag = string.format('"%s-%s-%x"', self.version, util.hash(relative), length)
  local headers = {
    ["Content-Type"] = mime.of(absolute),
    ["Cache-Control"] = self:cache_header(relative),
    ["ETag"] = etag,
    ["Vary"] = "Accept-Encoding",
  }

  if req:header("if-none-match") == etag then
    return response.new(304, "", headers)
  end

  if req.method ~= "GET" and req.method ~= "HEAD" then
    return response.text("405 Method Not Allowed\n", 405, { ["Allow"] = "GET, HEAD" })
  end

  local res = response.new(200, "", headers)
  res.file = { path = absolute, length = length, offset = 0 }
  res.content_length = length
  return res
end

static.Static = Static

return static
