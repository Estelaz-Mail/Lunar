local fs = require("lunar.core.fs")
local request = require("lunar.http.request")
local util = require("lunar.core.util")

local prerender = {}

local function copied(headers)
  local out = {}
  for name, value in pairs(headers or {}) do out[name] = value end
  return out
end

local function fixed(route)
  if not route.page then return false end
  for _, segment in ipairs(route.segments) do
    if segment.kind ~= "literal" then return false end
  end
  return true
end

function prerender.paths(app)
  local out = {}
  for _, route in ipairs(app.routes) do
    if fixed(route) then out[#out + 1] = route.id end
  end
  table.sort(out)
  return out
end

function prerender.declared(app)
  local setting = app.prerender
  if setting == nil or setting == false then return nil end
  if setting == true then return prerender.paths(app) end
  if type(setting) ~= "table" then return nil end

  local out = {}
  for _, path in ipairs(setting) do
    if type(path) == "string" and path:sub(1, 1) == "/" then out[#out + 1] = path end
  end
  return out
end

function prerender.file(path)
  if path == "/" then return "index.html" end
  return path:gsub("^/", ""):gsub("/$", "") .. "/index.html"
end

function prerender.one(app, path)
  local req = request.new({
    method = "GET",
    target = path,
    headers = { host = app.host or "localhost" },
  }, {})
  req.ip = "127.0.0.1"

  local ok, res = pcall(function() return app:handle(req) end)
  if not ok then return nil, tostring(res) end
  if type(res) ~= "table" then return nil, "no response" end
  if res.status ~= 200 then return nil, "answered " .. tostring(res.status) end
  if type(res.body) ~= "string" or res.body == "" then return nil, "answered nothing" end
  return res.body, res.headers
end

function prerender.run(app, options)
  options = options or {}
  local out = options.out or "output"
  local paths = options.paths or prerender.paths(app)

  local written, failed = {}, {}
  for _, path in ipairs(paths) do
    local body, err = prerender.one(app, path)
    if not body then
      failed[#failed + 1] = { path = path, reason = err }
    else
      local relative = prerender.file(path)
      local absolute = fs.join(out, relative)
      fs.mkdirp(fs.dirname(absolute))
      if util.write_file(absolute, body) then
        written[#written + 1] = { path = path, file = relative, bytes = #body }
      else
        failed[#failed + 1] = { path = path, reason = "could not write " .. absolute }
      end
    end
  end

  return { out = out, written = written, failed = failed }
end

function prerender.serve(app, req)
  if req.method ~= "GET" and req.method ~= "HEAD" then return nil end
  local held = app.prerendered
  if not held then return nil end
  local hit = held[req.path]
  if hit == nil then return nil end
  if hit == false then return nil end
  return { status = 200, body = hit.body, headers = copied(hit.headers) }
end

function prerender.warm(app)
  if app.prerendered then return app.prerendered end

  local held = {}
  app.prerendered = held

  for _, path in ipairs(prerender.declared(app) or {}) do
    local body, headers = prerender.one(app, path)
    held[path] = body and { body = body, headers = headers } or false
  end
  return held
end

return prerender
