local fs = require("lunar.core.fs")
local json = require("lunar.core.json")
local lunar = require("lunar")
local request = require("lunar.http.request")
local util = require("lunar.core.util")

local T = {}

local function temp_app(files)
  local root = fs.join(os.getenv("TMPDIR") or "/tmp",
    string.format("lunar-dev-%d-%d", os.time(), math.random(100000)))
  for relative, source in pairs(files) do
    local path = fs.join(root, relative)
    fs.mkdirp(fs.dirname(path))
    assert(util.write_file(path, source))
  end
  return root
end

local function get(instance, path, headers)
  local all = headers or {}
  all.host = "localhost"
  local req = request.new({ method = "GET", target = path, headers = all }, {})
  req.ip = "203.0.113.4"
  return instance:handler()(req)
end

local HOME = [[
<script>
  props { data = {} }
</script>
<h1>home</h1>
]]

local ABOUT = [[
<script>
  props { data = {} }
</script>
<h1>about</h1>
]]

function T.picks_up_a_new_route_without_a_restart()
  local root = temp_app({ ["orbit/page.lunar"] = HOME })
  local instance = lunar.app({ root = root, dev = true, version = "spec",
    watch_interval = 0 })

  assert(get(instance, "/").status == 200)
  assert(get(instance, "/about").status == 404, "there is no /about yet")

  fs.mkdirp(fs.join(root, "orbit/about"))
  assert(util.write_file(fs.join(root, "orbit/about/page.lunar"), ABOUT))

  local answer = get(instance, "/about")
  assert(answer.status == 200, "the new route answered " .. answer.status)
  assert(answer.body:find("<h1>about</h1>", 1, true), "and it is the new page")

  os.execute("rm -rf " .. root)
end

function T.forgets_a_route_that_was_deleted()
  local root = temp_app({
    ["orbit/page.lunar"] = HOME,
    ["orbit/about/page.lunar"] = ABOUT,
  })
  local instance = lunar.app({ root = root, dev = true, version = "spec",
    watch_interval = 0 })

  assert(get(instance, "/about").status == 200)
  os.remove(fs.join(root, "orbit/about/page.lunar"))
  assert(get(instance, "/about").status == 404, "the deleted route is gone")

  os.execute("rm -rf " .. root)
end

function T.reports_a_generation_that_moves_when_a_source_changes()
  local root = temp_app({ ["orbit/page.lunar"] = HOME })
  local instance = lunar.app({ root = root, dev = true, version = "spec",
    watch_interval = 0 })

  local first = json.decode(get(instance, "/_lunar/dev").body)
  assert(type(first.generation) == "number", "the endpoint reports a generation")
  local again = json.decode(get(instance, "/_lunar/dev").body)
  assert(again.generation == first.generation, "nothing changed, so it stood still")

  assert(util.write_file(fs.join(root, "orbit/page.lunar"), HOME .. "<p>more</p>\n"))
  local moved = json.decode(get(instance, "/_lunar/dev").body)
  assert(moved.generation > first.generation, "an edit moved it")

  local answer = get(instance, "/")
  assert(answer.body:find("<p>more</p>", 1, true), "and the page is the edited one")

  os.execute("rm -rf " .. root)
end

function T.watches_the_working_directory_when_the_app_is_the_root()
  local instance = lunar.app({ root = ".", dev = true, version = "spec",
    watch_interval = 0 })

  assert(instance.watcher ~= nil, "dev watches")
  instance:refresh(true)
  assert(next(instance.watcher.sources) ~= nil,
    "the working directory is what it watches")
end

function T.does_not_compress_in_development()
  local page = "<script>\n  props { data = {} }\n</script>\n<p>"
    .. string.rep("ordinary prose ", 200) .. "</p>\n"
  local root = temp_app({ ["orbit/page.lunar"] = page })

  local instance = lunar.app({ root = root, dev = true, version = "spec",
    watch_interval = 0 })
  local answer = get(instance, "/", { ["accept-encoding"] = "gzip" })
  assert(answer.headers["Content-Encoding"] == nil,
    "development keeps the bytes readable")

  local shipped = lunar.app({ root = root, dev = false, version = "spec" })
  local packed = get(shipped, "/", { ["accept-encoding"] = "gzip" })
  assert(packed.headers["Content-Encoding"] == "gzip", "production squeezes it")
  assert(#packed.body < #answer.body, "and it is smaller than the page")

  local asked = lunar.app({ root = root, dev = false, version = "spec",
    compress = false })
  local raw = get(asked, "/", { ["accept-encoding"] = "gzip" })
  assert(raw.headers["Content-Encoding"] == nil, "unless the app turns it off")

  os.execute("rm -rf " .. root)
end

function T.has_no_watcher_and_no_endpoint_in_production()
  local root = temp_app({ ["orbit/page.lunar"] = HOME })
  local instance = lunar.app({ root = root, dev = false, version = "spec" })

  assert(instance.watcher == nil, "production does not watch")
  assert(instance:generation() == 0)
  assert(get(instance, "/_lunar/dev").status == 404, "and does not answer the poll")

  os.execute("rm -rf " .. root)
end

function T.the_dev_bundle_carries_the_reloader_and_the_other_does_not()
  local root = temp_app({ ["orbit/page.lunar"] = HOME })
  local bundle = require("lunar.site.bundle")

  local development = lunar.app({ root = root, dev = true, version = "spec" })
  local source = assert(bundle.build(development))
  assert(source:find('package.preload["lunar.site.reload"]', 1, true),
    "the dev bundle carries the reloader")
  assert(source:find('require("lunar.site.reload").watch()', 1, true),
    "and starts it")

  local production = lunar.app({ root = root, dev = false, version = "spec" })
  local plain = assert(bundle.build(production))
  assert(not plain:find("lunar.site.reload", 1, true),
    "a production bundle carries nothing of the sort")

  os.execute("rm -rf " .. root)
end

function T.development_assets_do_not_use_stale_browser_caches()
  local root = temp_app({
    ["orbit/page.lunar"] = HOME,
    ["static/style.css"] = "body{color:red}",
    ["static/fonts/test.woff2"] = "font",
    ["static/icon.svg"] = '<svg xmlns="http://www.w3.org/2000/svg"/>',
  })
  local instance = lunar.app({ root = root, dev = true, version = "spec", watch_interval = 0 })
  local first = get(instance, "/style.css")
  assert(first.headers["Cache-Control"] == "no-store")
  assert(get(instance, "/fonts/test.woff2").headers["Cache-Control"] == "no-store")
  for _, name in ipairs({ "boot", "bridge", "lua54.wasm" }) do
    assert(get(instance, "/_lunar/runtime/" .. name).headers["Cache-Control"] == "no-store")
  end
  assert(util.write_file(fs.join(root, "static/style.css"), "body{color:tan}"))
  local edited = get(instance, "/style.css", { ["if-none-match"] = first.headers.ETag })
  assert(edited.status == 200, "an equal-length edit must not return a stale 304")
  assert(edited.headers.ETag == nil and first.headers.ETag == nil)
  assert(get(instance, "/style.css", { ["if-none-match"] = "*" }).status == 200)
  local before = instance:generation()
  assert(util.write_file(fs.join(root, "static/icon.svg"), '<svg xmlns="http://www.w3.org/2000/svg"><path/></svg>'))
  get(instance, "/_lunar/dev")
  assert(instance:generation() > before, "SVG edits trigger a reload")
  local production = lunar.app({ root = root, dev = false, version = "spec" })
  for _, name in ipairs({ "boot", "bridge", "lua54.wasm" }) do
    assert(get(production, "/_lunar/runtime/" .. name).headers["Cache-Control"]:find("immutable", 1, true))
  end
  assert(get(production, "/style.css").headers["Cache-Control"] == "public, max-age=3600")
  assert(get(production, "/fonts/test.woff2").headers["Cache-Control"]:find("immutable", 1, true))
  os.execute("rm -rf " .. root)
end

function T.every_development_response_disables_caching()
  local root = temp_app({
    ["orbit/page.lunar"] = HOME,
    ["orbit/cached/api.lua"] = [[
local response = require("lunar.http.response")
return { GET = function()
  return response.text("fresh", 200, {
    ["cache-control"] = "public, max-age=3600",
    ["Cloudflare-CDN-Cache-Control"] = "public, max-age=3600",
    ["ETag"] = '"cached"', ["Last-Modified"] = "yesterday", ["Expires"] = "tomorrow",
  })
end }
]],
  })
  local instance = lunar.app({ root = root, dev = true, version = "spec" })
  for _, path in ipairs({ "/", "/cached", "/missing", "/_lunar/dev", "/_lunar/moonlight.lua" }) do
    local answer = get(instance, path)
    assert(answer.headers["Cache-Control"] == "no-store", path)
    assert(answer.headers["CDN-Cache-Control"] == "no-store", path)
    assert(answer.headers["cache-control"] == nil)
    assert(answer.headers["Cloudflare-CDN-Cache-Control"] == nil)
    assert(answer.headers.ETag == nil and answer.headers["Last-Modified"] == nil)
    assert(answer.headers.Expires == nil)
  end
  assert(get(instance, "/cached").body == "fresh")
  os.execute("rm -rf " .. root)
end

function T.development_urls_change_after_edits_and_server_restarts()
  local root = temp_app({ ["orbit/page.lunar"] = HOME,
    ["app.html"] = '<html><head><link rel="stylesheet" href="/style.css?theme=dark#top">%lunar.head%</head><body>%lunar.body%</body></html>',
    ["static/style.css"] = "h1{color:red}",
  })
  local instance = lunar.app({ root = root, dev = true, version = "spec", watch_interval = 0 })
  local function revision(server)
    return assert(get(server, "/").body:match("__lunar_dev=([^#]+)#top"))
  end
  local first = revision(instance)
  assert(util.write_file(fs.join(root, "static/style.css"), "h1{color:tan}"))
  assert(revision(instance) ~= first)
  local restarted = lunar.app({ root = root, dev = true, version = "spec", watch_interval = 0 })
  assert(revision(restarted) ~= revision(instance))
  local original_poll = json.decode(get(instance, "/_lunar/dev").body)
  local restarted_poll = json.decode(get(restarted, "/_lunar/dev").body)
  assert(original_poll.session ~= restarted_poll.session)
  local production = lunar.app({ root = root, dev = false, version = "spec" })
  assert(not get(production, "/").body:find("__lunar_dev=", 1, true))
  os.execute("rm -rf " .. root)
end


function T.production_boot_urls_change_when_content_changes_without_a_version_bump()
  local root = temp_app({ ["orbit/page.lunar"] = HOME })
  local first = lunar.app({ root = root, dev = false, version = "unchanged" })
  local before = get(first, "/").body:match('src="(/_lunar/runtime/boot[^"]+)"')
  assert(before and before:find("build=", 1, true))
  assert(util.write_file(fs.join(root, "orbit/page.lunar"), HOME .. "<p>new revision</p>"))
  local second = lunar.app({ root = root, dev = false, version = "unchanged" })
  local after = get(second, "/").body:match('src="(/_lunar/runtime/boot[^"]+)"')
  assert(before ~= after, "an unchanged app version cannot reuse immutable runtime URLs")
  local chunk = second:chunk_url("/")
  assert(chunk and chunk:match("/[a-f0-9]+%.lua$"))
  assert(#chunk:match("/([a-f0-9]+)%.lua$") == 64)
  os.execute("rm -rf " .. root)
end

function T.multiple_apps_keep_their_imports_and_error_pages_isolated()
  local roots, apps = {}, {}
  for index = 1, 2 do
    roots[index] = temp_app({
      ["orbit/page.lunar"] = '<script>local Label = import("/lib/Label.lunar")</script><Label />',
      ["orbit/eclipse.lunar"] = '<script>local Label = import("/lib/Label.lunar")</script><Label />',
      ["orbit/failure/api.lua"] = 'return { GET = function() error("fixture failure") end }',
      ["lib/Label.lunar"] = "<h1>application " .. index .. "</h1>",
    })
    apps[index] = lunar.app({ root = roots[index], dev = false, client = false })
  end
  for _, index in ipairs({ 1, 2, 1 }) do
    for _, path in ipairs({ "/", "/failure" }) do
      local answer = get(apps[index], path)
      assert(answer.body:find("<h1>application " .. index .. "</h1>", 1, true), path)
    end
  end
  for _, root in ipairs(roots) do os.execute("rm -rf " .. root) end
end

function T.compile_errors_are_reported_once_and_do_not_break_the_error_page()
  local root = temp_app({
    ["orbit/page.lunar"] = "<h1>Broken page</h1>\n</code>",
    ["orbit/eclipse.lunar"] = '<script>props { data = {} }</script><h1>Custom error</h1><p>{data.status}</p>',
  })
  local output = {}
  local stream = { write = function(_, ...)
    for index = 1, select("#", ...) do output[#output + 1] = tostring(select(index, ...)) end
  end, flush = function() end }
  local instance = lunar.app({ root = root, dev = true, watch_interval = 0, error_stream = stream })
  local answer = get(instance, "/")
  assert(answer.status == 500 and answer.body:find("Custom error", 1, true))
  assert(not answer.body:find("/_lunar/runtime/boot", 1, true))
  assert(answer.body:find("/_lunar/runtime/reload?", 1, true))
  assert(answer.body:find('integrity="sha256-', 1, true))
  local count = #output
  get(instance, "/")
  get(instance, "/missing")
  assert(#output == count, "repeated requests must not duplicate the compilation error")
  local log = table.concat(output)
  assert(log:find("orbit/page.lunar:2", 1, true))
  assert(log:find("</code> with no element open", 1, true))
  assert(not log:find("Error page failed", 1, true))
  local reload = get(instance, "/_lunar/runtime/reload")
  assert(reload.status == 200 and reload.headers["Cache-Control"] == "no-store")
  assert(util.write_file(fs.join(root, "orbit/page.lunar"), "<h1>Fixed page</h1>"))
  assert(get(instance, "/").status == 200)
  assert(util.write_file(fs.join(root, "orbit/page.lunar"), "<h1>Broken again</h1>\n</code>"))
  assert(get(instance, "/").status == 500)
  assert(#output > count, "a new edit may report the error again")
  os.execute("rm -rf " .. root)
end

function T.broken_error_components_still_return_a_reloadable_fallback()
  local root = temp_app({
    ["orbit/page.lunar"] = "</code>",
    ["orbit/eclipse.lunar"] = "</h1>",
  })
  local instance = lunar.app({ root = root, dev = true,
    error_stream = { write = function() end, flush = function() end } })
  local answer = get(instance, "/")
  assert(answer.status == 500)
  assert(answer.body:find("500 Internal Server Error", 1, true))
  assert(answer.body:find("/_lunar/runtime/reload?", 1, true))
  assert(not answer.body:find("/_lunar/runtime/boot", 1, true))
  os.execute("rm -rf " .. root)
end

return T
