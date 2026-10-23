local fetch = dofile(".lunar/workers/src/app.lua")
local json = require("lunar.core.json")
local signal = require("lunar.runtime.signal")
local function request(path)
  local result = fetch(json.encode({ method = "GET", url = "https://lunar.estelaz.com" .. path, headers = {} }))
  return assert(json.decode(result))
end
local seen, dispose = {}, {}
local state = signal.new(0)
for i = 1, 12 do
  dispose[i] = signal.effect(function() seen[i] = signal.get(state) end)
end
for value = 1, 3 do
  signal.set(state, value)
  for i = 1, 12 do assert(seen[i] == value, "reactivity skipped a subscriber") end
end
for _, fn in ipairs(dispose) do fn() end
local docs = require("docs")
local paths = { "/" }
for _, page in ipairs(docs) do paths[#paths + 1] = "/docs/" .. page.slug end
for _, path in ipairs(paths) do
  local result = request(path)
  assert(result.status == 200, path .. " failed to render")
  assert(result.body:find('<html lang="pt%-BR">'), path .. " has wrong language")
  assert(result.body:find('<link rel="canonical"'), path .. " has no canonical URL")
  assert(result.body:find('<title>'), path .. " has no title")
  assert(result.headers["Content-Security-Policy"]:find("script%-src 'self'"), "CSP missing")
  assert(not result.headers["Content-Security-Policy"]:find("unsafe%-eval"), "CSP permits unsafe eval")
  print("ok " .. path)
end
local redirect = request("/docs")
assert(redirect.status == 302 and redirect.headers.Location == "/docs/introducao", "docs redirect failed")
for _, path in ipairs({ "/missing", "/docs/missing" }) do
  local result = request(path)
  assert(result.status == 404, "unknown route must return 404")
  assert(result.body:find('name="robots" content="noindex"'), "error page must not be indexed")
end
print("ok redirects, 404 pages, CSP, metadata and 12 reactive subscribers")
