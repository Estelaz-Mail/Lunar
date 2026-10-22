local json = require("lunar.core.json")

local response = {}

local STATUS_TEXT = {
  [200] = "OK", [201] = "Created", [204] = "No Content",
  [301] = "Moved Permanently", [302] = "Found", [303] = "See Other",
  [304] = "Not Modified", [307] = "Temporary Redirect", [308] = "Permanent Redirect",
  [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden",
  [404] = "Not Found", [405] = "Method Not Allowed", [408] = "Request Timeout",
  [409] = "Conflict", [413] = "Content Too Large", [414] = "URI Too Long",
  [415] = "Unsupported Media Type", [422] = "Unprocessable Content",
  [429] = "Too Many Requests", [431] = "Request Header Fields Too Large",
  [500] = "Internal Server Error", [501] = "Not Implemented",
  [502] = "Bad Gateway", [503] = "Service Unavailable",
}

function response.status_text(status)
  return STATUS_TEXT[status] or "Unknown"
end

local function with(base, extra)
  local out = {}
  for name, value in pairs(base or {}) do out[name] = value end
  for name, value in pairs(extra or {}) do out[name] = value end
  return out
end

function response.new(status, body, headers)
  return { status = status or 200, body = body or "", headers = headers or {} }
end

function response.html(body, status, headers)
  return response.new(status or 200, body,
    with({ ["Content-Type"] = "text/html; charset=utf-8" }, headers))
end

function response.text(body, status, headers)
  return response.new(status or 200, body,
    with({ ["Content-Type"] = "text/plain; charset=utf-8" }, headers))
end

function response.json(value, status, headers)
  return response.new(status or 200, json.encode(value),
    with({ ["Content-Type"] = "application/json; charset=utf-8" }, headers))
end

function response.redirect(location, status)
  return response.new(status or 302, "",
    { ["Location"] = location, ["Content-Type"] = "text/plain; charset=utf-8" })
end

function response.no_content(headers)
  return response.new(204, "", headers or {})
end

function response.coerce(value)
  if value == nil then return nil end
  if type(value) == "string" then return response.html(value) end
  if type(value) == "table" then
    if value.status or value.headers or value.body ~= nil then
      value.status = value.status or 200
      value.headers = value.headers or {}
      value.body = value.body or ""
      return value
    end
    return response.json(value)
  end
  return response.text(tostring(value))
end

function response.strip_body(res)
  res.headers["Content-Length"] = tostring(res.content_length or #(res.body or ""))
  res.body = ""
  res.file = nil
  return res
end

return response
