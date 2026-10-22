local app_lib = require("lunar.site.app")
local json = require("lunar.core.json")
local request_lib = require("lunar.http.request")
local response_lib = require("lunar.http.response")
local url_lib = require("lunar.core.url")

local worker = {}

function worker.app(manifest)
  return app_lib.frozen(manifest)
end

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
    ip = payload.ip or headers["cf-connecting-ip"],
  }, {})

  req.scheme = scheme_of(href)
  req.origin = req.scheme .. "://" .. req.host
  return req
end

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
    body = ""
  end
  if res.stream then
    local collected, collect_err = response_lib.collect(res)
    if not collected then
      return worker.encode({
        status = 500,
        headers = { ["Content-Type"] = "text/plain; charset=utf-8" },
        body = "500 Internal Server Error\n",
      }, as_text)
    end
    body = collected.body
  end

  local headers = {}
  for name, value in pairs(res.headers or {}) do
    if type(value) == "table" then
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
