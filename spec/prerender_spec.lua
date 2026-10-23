local fs = require("lunar.core.fs")
local lunar = require("lunar")
local prerender = require("lunar.site.prerender")
local request = require("lunar.http.request")
local util = require("lunar.core.util")

local T = {}

local function get(instance, path, headers)
  local all = headers or {}
  all.host = "localhost"
  local req = request.new({ method = "GET", target = path, headers = all }, {})
  req.ip = "203.0.113.9"
  return instance:handler()(req)
end

local function app(options)
  local settings = { root = "examples/tranquility", dev = false, version = "spec",
    compress = false, rate_limit = { enabled = false } }
  for key, value in pairs(options or {}) do settings[key] = value end
  return lunar.app(settings)
end

function T.renders_every_route_that_has_no_parameter()
  local paths = prerender.paths(app())
  local found = {}
  for _, path in ipairs(paths) do found[path] = true end

  assert(found["/"], "the home page is fixed")
  assert(found["/about"], "and so is /about")
  assert(not found["/blog/[slug]"], "a route with a parameter is not")
  for _, path in ipairs(paths) do
    assert(not path:find("%["), path .. " still carries a parameter")
  end
end

function T.lays_the_files_out_the_way_a_static_host_expects()
  assert(prerender.file("/") == "index.html")
  assert(prerender.file("/about") == "about/index.html")
  assert(prerender.file("/blog/lua") == "blog/lua/index.html")
end

function T.writes_what_the_server_would_have_answered()
  local instance = app()
  local root = fs.join(os.getenv("TMPDIR") or "/tmp",
    string.format("lunar-prerender-%d-%d", os.time(), math.random(100000)))

  local result = prerender.run(instance, { out = root })
  assert(#result.failed == 0, "nothing failed")
  assert(#result.written >= 3, "it wrote the fixed routes")

  for _, item in ipairs(result.written) do
    local written = util.read_file(fs.join(root, item.file))
    assert(written and #written == item.bytes, item.file .. " is on disk")
    assert(written == get(instance, item.path).body,
      item.path .. " was written as the server renders it")
    assert(written:find("<!DOCTYPE html>", 1, true) or written:find("<!doctype html>", 1, true),
      item.file .. " is a document")
  end

  os.execute("rm -rf " .. root)
end

function T.serves_a_declared_path_from_memory()
  local instance = app({ prerender = { "/about" } })

  local first = get(instance, "/about")
  assert(first.status == 200)
  assert(instance.prerendered["/about"], "it was rendered and kept")

  instance.prerendered["/about"].body = "<p>from the cache</p>"
  local second = get(instance, "/about")
  assert(second.body == "<p>from the cache</p>", "the second answer came from memory")

  local other = get(instance, "/")
  assert(other.body ~= "<p>from the cache</p>", "a path nobody declared is rendered")
end

function T.does_not_hold_anything_in_development()
  local instance = app({ dev = true, prerender = true })
  get(instance, "/about")
  assert(instance.prerendered == nil, "development always renders afresh")
end

function T.warming_does_not_call_itself()
  local instance = app({ prerender = true })
  local held = prerender.warm(instance)
  assert(held, "it warmed")
  local count = 0
  for _ in pairs(held) do count = count + 1 end
  assert(count == #prerender.paths(instance), "every fixed route is held")
  assert(prerender.warm(instance) == held, "and warming again is the same table")
end

function T.reads_the_setting_from_the_manifest()
  local manifest = require("lunar.site.manifest")
  local root = fs.join(os.getenv("TMPDIR") or "/tmp",
    string.format("lunar-manifest-%d-%d", os.time(), math.random(100000)))
  fs.mkdirp(root)

  assert(util.write_file(fs.join(root, "lunar.json"), '{ "prerender": true }'))
  assert(manifest.read(root).prerender == true)

  assert(util.write_file(fs.join(root, "lunar.json"), '{ "prerender": ["/", "/about"] }'))
  assert(#manifest.read(root).prerender == 2)

  assert(util.write_file(fs.join(root, "lunar.json"), '{ "prerender": ["about"] }'))
  local bad, err = manifest.read(root)
  assert(bad == nil and err:find("must be a path", 1, true), tostring(err))

  assert(util.write_file(fs.join(root, "lunar.json"), '{ "prerender": 3 }'))
  local wrong, message = manifest.read(root)
  assert(wrong == nil and message:find("boolean or a list", 1, true), tostring(message))

  os.execute("rm -rf " .. root)
end


function T.prerendered_documents_do_not_replace_navigation_json()
  local instance = app({ prerender = true })
  local document = get(instance, "/about")
  assert(document.headers["Content-Type"]:find("text/html", 1, true))
  local navigation = get(instance, "/about", { accept = "application/json" })
  assert(navigation.headers["Content-Type"]:find("application/json", 1, true))
  assert(require("lunar.core.json").decode(navigation.body).route == "/about")
end

function T.heads_preserve_get_encoding_and_length_without_a_body()
  for _, setting in ipairs({ false, true }) do
    local instance = app({ prerender = setting, compress = true })
    local headers = { ["accept-encoding"] = "gzip" }
    local document = get(instance, "/about", headers)
    local req = request.new({ method = "HEAD", target = "/about", headers = headers }, {})
    local head = instance:handler()(req)
    assert(head.status == document.status)
    assert(head.body == "" and head.file == nil and head.stream == nil)
    assert(head.headers["Content-Encoding"] == document.headers["Content-Encoding"])
    assert(tonumber(head.headers["Content-Length"]) == #document.body)
  end
end

return T
