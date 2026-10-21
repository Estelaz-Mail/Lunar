--- The request bridge for a platform that has no sockets.
--
-- Cloudflare Workers hands a Lua app a request as data and wants a response
-- back as data; there is no listener, no connection and no file. Everything
-- between those two points is the same `App:handler()` the HTTP server calls,
-- so a page renders identically whether it was served from a socket or from
-- an edge runtime.
--
-- The bridge is JSON, because that is the one shape both sides already speak.
-- A body is a string: this is for pages, endpoints and form posts, not for
-- streaming a video out of a Worker.

local app_lib = require("lunar.site.app")
local json = require("lunar.core.json")
local request_lib = require("lunar.http.request")
local url_lib = require("lunar.core.url")

local worker = {}

--- Builds the app from the manifest the bundle carries.
function worker.app(manifest)
  return app_lib.frozen(manifest)
end

--- The path and query of an absolute URL, which is what a request target is.
local function target_of(href)
  local rest = href:match("^%a[%w+.-]*://[^/]*(/.*)$")
  if not rest or rest == "" then return "/" end
  return rest
end

local function host_of(href)
  return (href:match("^%a[%w+.-]*://([^/]+)")) or "localhost"
end

local function scheme_of(href)
  return (href:match("^(%a[%w+.-]*)://")) or "https"
end

--- Turns the platform's request into one of Lunar's.
--
-- The scheme and host come from the URL the platform resolved, not from a
-- header a client could set, so there is nothing to trust or not trust here.
function worker.request(payload)
  local href = payload.url or "https://localhost/"
  local headers = {}
  for name, value in pairs(payload.headers or {}) do
    headers[tostring(name):lower()] = tostring(value)
  end
  headers.host = headers.host or host_of(href)

  local req = request_lib.new({
    method = payload.method or "GET",
    target = target_of(href),
    headers = headers,
    body = payload.body,
    -- The edge has already resolved who is asking; `CF-Connecting-IP` is set
    -- by the platform and cannot be spoofed by the client.
    ip = payload.ip or headers["cf-connecting-ip"],
  }, {})

  -- `request.new` derives the scheme from the forwarded headers, which are not
  -- how this platform says it. The URL is authoritative.
  req.scheme = scheme_of(href)
  req.origin = req.scheme .. "://" .. req.host
  return req
end

--- Serves one request. `payload` is a table or a JSON string; the result is of
-- the same kind, so the JavaScript side can hand over a string and get one
-- back without knowing anything about Lua values.
function worker.handle(app, payload)
  local as_text = type(payload) == "string"
  local decoded = payload
  if as_text then
    local value, err = json.decode(payload)
    if not value then
      return worker.encode({ status = 400, body = "bad request: " .. tostring(err) }, as_text)
    end
    decoded = value
  end

  local req = worker.request(decoded)
  local ok, res = pcall(app:handler(), req)
  if not ok then
    -- Whatever the host gives us for a log. An edge runtime may have neither
    -- `io.stderr` nor `print`, and a failure to report a failure should not
    -- become the failure.
    pcall(function()
      if io and io.stderr then io.stderr:write("lunar: ", tostring(res), "\n")
      else print("lunar: " .. tostring(res)) end
    end)
    return worker.encode({
      status = 500,
      headers = { ["Content-Type"] = "text/plain; charset=utf-8" },
      body = "500 Internal Server Error\n",
    }, as_text)
  end

  local body = res.body or ""
  if res.file then
    -- A frozen app never answers with a file: the platform serves those. If
    -- one gets here it is a bug, and an empty body is the honest answer.
    body = ""
  end

  local headers = {}
  for name, value in pairs(res.headers or {}) do
    if type(value) == "table" then
      -- The platform's header API takes one value, so a repeated header is
      -- joined the way HTTP joins one.
      headers[name] = table.concat(value, ", ")
    else
      headers[name] = tostring(value)
    end
  end

  return worker.encode({ status = res.status or 200, headers = headers, body = body }, as_text)
end

function worker.encode(value, as_text)
  if not as_text then return value end
  return json.encode(value)
end

worker.target_of = target_of
worker.url = url_lib

return worker
