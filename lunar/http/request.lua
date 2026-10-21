--- Requests.
--
-- Built from the raw HTTP head by `http.server`, or by hand in a spec. The
-- body is read lazily, so a GET never waits on a socket read it does not need.

local json = require("lunar.core.json")
local url = require("lunar.core.url")
local util = require("lunar.core.util")

local request = {}

local Request = {}
Request.__index = Request

function Request:header(name)
  return self.headers[name:lower()]
end

function Request:read_body()
  if self.body ~= nil then return self.body end
  self.body = (self.read_body_fn and self.read_body_fn()) or ""
  return self.body
end

--- The body as JSON, or nil and a message. A handler should never have to
-- wrap this in a pcall itself.
function Request:json()
  return json.decode(self:read_body())
end

--- The body as a form. `application/x-www-form-urlencoded` is what a `<form>`
-- without JavaScript sends, which is the form this framework cares about.
function Request:form()
  local kind = (self:header("content-type") or ""):lower()
  if kind:find("application/json", 1, true) then
    local value = self:json()
    return type(value) == "table" and value or {}
  end
  return url.parse_query(self:read_body())
end

function Request:is_head() return self.method == "HEAD" end

--- Whether the client asked for JSON rather than a page, which is how the
-- client-side router asks for a route's data.
function Request:wants_json()
  local accept = self:header("accept") or ""
  return accept:find("application/json", 1, true) ~= nil
end

local function resolve_origin(headers, options)
  local scheme = options.default_scheme or "http"
  local host = headers["host"] or options.default_host or "localhost"

  if options.trust_forwarded then
    local forwarded_proto = headers[options.protocol_header or "x-forwarded-proto"]
    if forwarded_proto then
      scheme = util.trim(util.split(forwarded_proto, ",")[1] or ""):lower()
    end
    local forwarded_host = headers[options.host_header or "x-forwarded-host"]
    if forwarded_host then
      host = util.trim(util.split(forwarded_host, ",")[1] or "")
    end
  end

  if scheme ~= "http" and scheme ~= "https" then scheme = "http" end
  -- A Host header is attacker-controlled in shape, if not in value. Anything
  -- that is not a hostname[:port] is replaced rather than parsed.
  if not host:match("^[%w%.%-%_]+:?%d*$") and not host:match("^%[[%x:]+%]:?%d*$") then
    host = options.default_host or "localhost"
  end
  return scheme, host
end

function request.new(fields, options)
  options = options or {}
  local headers = {}
  for name, value in pairs(fields.headers or {}) do headers[name:lower()] = value end

  local target = fields.target or "/"
  if not target:match("^/") then
    local parsed = target:match("^%a[%w+.-]*://[^/]*(/.*)$")
    target = parsed or "/"
  end

  local scheme, host = resolve_origin(headers, options)
  local parsed = url.parse(target)

  local self = setmetatable({
    method = (fields.method or "GET"):upper(),
    target = target,
    version = fields.version or "HTTP/1.1",
    headers = headers,
    scheme = scheme,
    host = host,
    origin = scheme .. "://" .. host,
    path = parsed.path,
    raw_path = parsed.raw_path,
    search = parsed.search,
    query = parsed.query,
    params = fields.params or {},
    ip = fields.ip,
    read_body_fn = fields.read_body_fn,
    body = fields.body,
    locals = {},
  }, Request)

  if options.trust_forwarded and options.address_header then
    local forwarded_for = headers[options.address_header]
    if forwarded_for then
      local hops = util.split(forwarded_for, ",")
      local depth = options.xff_depth or 1
      local hop = hops[math.max(1, #hops - depth + 1)]
      if hop then self.ip = util.trim(hop) end
    end
  end

  return self
end

request.Request = Request

return request
