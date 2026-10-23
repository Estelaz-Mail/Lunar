local json = require("lunar.core.json")
local lunar = require("lunar")
local request = require("lunar.http.request")
local routes_lib = require("lunar.site.routes")

local T = {}

local APP = "examples/tranquility"

local function app(options)
  local merged = { root = APP, dev = true, version = "spec" }
  for key, value in pairs(options or {}) do merged[key] = value end
  return lunar.app(merged)
end

local shared = app()

local function send(instance, method, path, headers, body)
  local all = headers or {}
  all.host = all.host or "localhost"
  local req = request.new({
    method = method, target = path, headers = all, body = body,
  }, {})
  req.ip = "203.0.113.9"
  return instance:handler()(req)
end

local function get(path, headers, instance)
  return send(instance or shared, "GET", path, headers)
end

local function stub_probe(instance, path, probe)
  local util = require("lunar.core.util")
  instance.modules[path] = {
    source = assert(util.read_file(path)),
    module = { probe = probe },
  }
end


function T.matches_a_literal_route_before_a_dynamic_one()
  local list = {
    { id = "/blog/[slug]", segments = routes_lib.compile("/blog/[slug]") },
    { id = "/blog/new", segments = routes_lib.compile("/blog/new") },
    { id = "/[...path]", segments = routes_lib.compile("/[...path]") },
  }
  table.sort(list, function(a, b) return #a.id > #b.id end)

  local discovered = app().routes
  local route = routes_lib.match(discovered, "/blog")
  assert(route.id == "/blog")
  local dynamic, params = routes_lib.match(discovered, "/blog/why-lua")
  assert(dynamic.id == "/blog/[slug]")
  assert(params.slug == "why-lua")
  assert(routes_lib.match(discovered, "/") .id == "/")
  assert(routes_lib.match(discovered, "/nope") == nil)
end

function T.matches_a_catch_all_and_hands_over_the_rest_of_the_path()
  local segments = routes_lib.compile("/files/[...path]")
  local params = routes_lib.match_segments(segments, { "files", "a", "b", "c.txt" })
  assert(params.path == "a/b/c.txt")
  assert(routes_lib.match_segments(segments, { "files" }).path == "")
  assert(routes_lib.match_segments(segments, { "other" }) == nil)
end

function T.a_group_directory_contributes_no_segment()
  assert(routes_lib.route_id("(marketing)/about") == "/about")
  assert(routes_lib.route_id("") == "/")
  assert(routes_lib.route_id("blog/[slug]") == "/blog/[slug]")
end


function T.renders_a_page_inside_its_shell()
  local res = get("/")
  assert(res.status == 200)
  assert(res.headers["Content-Type"] == "text/html; charset=utf-8")
  assert(res.body:find('class="brand', 1, true))
  assert(res.body:find("Rendered by Lunar", 1, true))
  assert(res.body:find("A framework in Lua", 1, true))
  assert(res.body:find('class="counter', 1, true))
  assert(res.body:find('href="/css/app.css?__lunar_dev=', 1, true))
end

function T.gives_a_page_the_data_of_the_shells_above_it()
  local res = get("/blog")
  assert(res.body:find("Why Lua, for both halves", 1, true))
  local payload = json.decode(res.body:match('id="lunar%-data">(.-)</script>'))
  assert(payload.data[1].site == "Lunar", "the shell's level has its own data")
  assert(payload.data[2].site == "Lunar", "and the page's level inherited it")
  assert(payload.data[2].posts ~= nil)
  assert(payload.data[1].posts == nil, "the shell did not inherit the page's")
end

function T.puts_the_title_from_the_head_in_the_document()
  assert(get("/").body:find("<title>Lunar</title>", 1, true))
  local body = get("/").body:match("<body>(.*)</body>")
  assert(not body:find("<title", 1, true))
end

function T.collects_only_the_styles_of_the_components_it_rendered()
  local home = get("/").body
  assert(home:find("%.counter%.l%-%x+"), "the counter's styles are there")
  assert(not home:find("%.posts%.l%-%x+"), "the blog list's are not")
  local blog = get("/blog").body
  assert(blog:find("%.posts%.l%-%x+"))
  assert(not blog:find("%.counter%.l%-%x+"))
end

function T.reads_the_query_string_in_a_probe()
  assert(get("/?start=7").body:find(">7<", 1, true))
end

function T.answers_the_client_router_with_json()
  local res = get("/blog", { accept = "application/json" })
  assert(res.status == 200)
  assert(res.headers["Content-Type"] == "application/json; charset=utf-8")
  assert(res.headers["Vary"] == "Accept")
  local payload = json.decode(res.body)
  assert(payload.route == "/blog")
  assert(#payload.data == 2, "one level of data per component that draws")
  assert(not res.body:find("<div", 1, true), "no markup in a data response")
end

function T.passes_the_parameters_of_a_dynamic_route()
  local res = get("/blog/globals-are-state")
  assert(res.status == 200)
  assert(res.body:find("A global in a component script is state", 1, true))
  assert(res.body:find("<code>function(_ENV) … end</code>", 1, true))
end


function T.shows_the_eclipse_when_a_probe_fails_the_request()
  local res = get("/blog/not-a-post")
  assert(res.status == 404)
  assert(res.headers["Cache-Control"] == "no-store")
  assert(res.body:find("No post called", 1, true), "the message reached the page")
  assert(res.body:find('class="status', 1, true), "the app's own eclipse rendered")
end

function T.shows_the_eclipse_for_a_path_that_is_not_a_route()
  local res = get("/nothing/here")
  assert(res.status == 404)
  assert(res.body:find('class="status', 1, true))
end

function T.turns_a_crash_in_a_probe_into_a_500()
  local instance = app()
  stub_probe(instance, APP .. "/orbit/about/page.lua", function()
    error("the database is on fire")
  end)
  instance.dev = false
  local res = send(instance, "GET", "/about")
  assert(res.status == 500)
  assert(not res.body:find("on fire", 1, true),
    "a production error page says nothing about the inside of the server")

  instance.dev = true
  assert(send(instance, "GET", "/about").body:find("on fire", 1, true),
    "in development it says exactly what happened")
end

function T.refuses_a_probe_that_does_not_return_a_table()
  local instance = app()
  stub_probe(instance, APP .. "/orbit/about/page.lua", function() return "nope" end)
  local res = send(instance, "GET", "/about")
  assert(res.status == 500)
  assert(res.body:find("must return a table", 1, true))
end

function T.redirects_when_a_probe_says_to()
  local instance = app()
  stub_probe(instance, APP .. "/orbit/about/page.lua", function(event)
    event.redirect(308, "/elsewhere")
  end)
  local res = send(instance, "GET", "/about")
  assert(res.status == 308)
  assert(res.headers["Location"] == "/elsewhere")
end


function T.serves_an_endpoint_and_turns_a_table_into_json()
  local res = get("/api/time")
  assert(res.status == 200)
  local payload = json.decode(res.body)
  assert(payload.route == "/api/time")
  assert(payload.now:match("^%d%d%d%d%-%d%d%-%d%dT"))
end

function T.reads_a_form_body_in_an_endpoint()
  local res = send(shared, "POST", "/api/time",
    { ["content-type"] = "application/x-www-form-urlencoded" }, "echo=hello%20there")
  assert(res.status == 200)
  assert(json.decode(res.body).echoed == "hello there")
end

function T.lets_an_endpoint_answer_with_a_status_of_its_own()
  local res = send(shared, "POST", "/api/time",
    { ["content-type"] = "application/x-www-form-urlencoded" }, "nothing=here")
  assert(res.status == 422)
end

function T.answers_405_with_the_methods_there_are()
  local res = send(shared, "DELETE", "/api/time")
  assert(res.status == 405)
  assert(res.headers["Allow"] == "GET, POST")
end

function T.refuses_a_write_to_a_page()
  local res = send(shared, "POST", "/about")
  assert(res.status == 405)
  assert(res.headers["Allow"] == "GET, HEAD")
end


function T.serves_the_apps_static_files()
  local res = get("/css/app.css")
  assert(res.status == 200)
  assert(res.headers["Content-Type"] == "text/css; charset=utf-8")
  assert(res.headers["ETag"] == nil)
  assert(res.file.length > 0)
end

function T.revalidates_a_file_against_its_etag()
  local production = app({ dev = false })
  local etag = get("/css/app.css", nil, production).headers["ETag"]
  local res = get("/css/app.css", { ["if-none-match"] = etag }, production)
  assert(res.status == 304)
  assert(res.file == nil)
end

function T.will_not_serve_a_file_outside_the_static_root()
  assert(get("/../lunar/core/util.lua").status == 404)
  assert(get("/%2e%2e/%2e%2e/etc/passwd").status == 404)
  assert(get("/.env").status == 404)
end

function T.serves_the_moonlight_bundle_and_lua54_runtime()
  local bundle = get("/_lunar/moonlight.lua")
  assert(bundle.status == 200)
  assert(bundle.headers["Content-Type"] == "text/x-lua; charset=utf-8")
  assert(bundle.body:find("package.preload", 1, true))

  for _, name in ipairs({ "boot", "bridge", "lua54.wasm" }) do
    local runtime = get("/_lunar/runtime/" .. name)
    assert(runtime.status == 200, name)
    assert(runtime.headers["Cache-Control"] == "no-store")
    assert(runtime.headers["Content-Type"]:find(name:match("%.wasm$")
      and "application/wasm" or "text/javascript", 1, true))
  end
  assert(get("/_lunar/runtime/../bridge.c").status == 404)
end

function T.a_head_request_has_the_length_but_no_body()
  local res = send(shared, "HEAD", "/")
  assert(res.status == 200)
  assert(res.body == "")
  assert(tonumber(res.headers["Content-Length"]) > 0)
end


function T.sends_the_security_headers_on_every_response()
  for _, path in ipairs({ "/", "/api/time", "/css/app.css", "/nothing" }) do
    local res = get(path)
    assert(res.headers["X-Content-Type-Options"] == "nosniff", path)
    assert(res.headers["Content-Security-Policy"] ~= nil, path)
    assert(res.headers["Referrer-Policy"] ~= nil, path)
  end

  local page = get("/")
  assert(page.headers["Content-Security-Policy"]:find("default-src 'none'", 1, true))
  assert(page.headers["Permissions-Policy"]:find("camera=()", 1, true))

  local file = get("/css/app.css")
  assert(file.headers["Content-Security-Policy"]:find("sandbox", 1, true))
  assert(file.headers["Permissions-Policy"] == nil)
end

function T.the_document_needs_no_exception_to_its_own_policy()
  local res = get("/")
  local policy = res.headers["Content-Security-Policy"]
  assert(policy:find("script%-src 'self'"))
  assert(policy:find("'wasm-unsafe-eval'", 1, true))
  assert(not policy:find("'unsafe-eval'", 1, true))
  assert(not policy:find("unsafe%-inline.-script"))
  assert(not policy:find("nonce", 1, true))
  assert(res.body:find('id="lunar%-integrity"'))
  assert(res.body:find('integrity="sha256%-'))

  for attributes in res.body:gmatch("<script([^>]*)>") do
    assert(attributes:find("src=", 1, true)
      or attributes:find('type="application/json"', 1, true),
      "an inline script the policy would block: <script" .. attributes .. ">")
  end
  assert(not res.body:find(" on%a+=\""), "an inline handler the policy would block")
end

function T.rate_limits_a_flood_from_one_address()
  local instance = app({ rate_limit = {
    classes = {
      page = { capacity = 2, per_second = 1 },
      asset = { capacity = 2, per_second = 1 },
      write = { capacity = 1, per_second = 1 },
    },
  } })

  assert(send(instance, "GET", "/").status == 200)
  assert(send(instance, "GET", "/").status == 200)
  local refused = send(instance, "GET", "/")
  assert(refused.status == 429)
  assert(refused.headers["Retry-After"] == "1")
  assert(send(instance, "GET", "/css/app.css").status == 200)
end

function T.serves_the_wasm_parts_and_the_index_that_points_at_them()
  local index = get("/_lunar/wasm/index.json")
  assert(index.status == 200, index.status)
  assert(index.headers["Content-Type"]:find("json", 1, true))
  local decoded = json.decode(index.body)
  assert(decoded.index.area == "geometry", "the index says which part exports what")
  assert(decoded.index.basel == "series")
  assert(table.concat(decoded.parts.series.needs, ",") == "geometry")
  assert(#decoded.parts.geometry.needs == 0)

  local part = get("/_lunar/wasm/geometry.wasm")
  assert(part.status == 200)
  assert(part.headers["Content-Type"] == "application/wasm")
  assert(part.body:sub(1, 4) == "\0asm", "those are wasm bytes")
  assert(part.headers["ETag"] == nil)

  assert(get("/_lunar/wasm/nothing.wasm").status == 404)
end

return T
