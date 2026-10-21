--- The HTTP layer: the protocol's sharp edges, the router, and the headers.

local ratelimit = require("lunar.http.ratelimit")
local request = require("lunar.http.request")
local response = require("lunar.http.response")
local router_lib = require("lunar.http.router")
local security = require("lunar.http.security")
local server = require("lunar.http.server")
local static_lib = require("lunar.http.static")
local url = require("lunar.core.url")

local T = {}

local function make(method, target, headers, options)
  local all = headers or {}
  all.host = all.host or "example.test"
  return request.new({ method = method or "GET", target = target or "/", headers = all },
    options or {})
end

-- The protocol ------------------------------------------------------------------

--- The path reaches a handler percent-decoded, so a CRLF that arrives encoded
-- would otherwise end up in a response header. This is the last place that can
-- answer 400.
function T.refuses_a_target_carrying_a_control_byte()
  assert(server.target_is_safe("/a/b?c=1"))
  assert(server.target_is_safe("/a%20b"))
  assert(server.target_is_safe("/caf%C3%A9"))
  assert(not server.target_is_safe("/a\rb"))
  assert(not server.target_is_safe("/a%0d%0aX-Evil:%201"))
  assert(not server.target_is_safe("/a%00b"))
  assert(not server.target_is_safe("/a%7f"))
end

--- A request whose body length is ambiguous is refused rather than guessed
-- at: a server that guesses differently from the proxy in front of it is how a
-- request gets smuggled past that proxy.
function T.refuses_an_ambiguous_message_length()
  assert(server.check_framing({}) == nil)
  assert(server.check_framing({ ["content-length"] = "12" }) == nil)
  assert(server.check_framing({ ["transfer-encoding"] = "chunked" }) == nil)

  assert(server.check_framing({ ["transfer-encoding"] = "chunked",
    ["content-length"] = "1" }) == 400)
  assert(server.check_framing({ ["transfer-encoding"] = "gzip" }) == 501)
  -- Two Content-Lengths arrive joined with ", ".
  assert(server.check_framing({ ["content-length"] = "1, 2" }) == 400)
  assert(server.check_framing({ ["content-length"] = "0x10" }) == 400)
  assert(server.check_framing({ ["content-length"] = "-1" }) == 400)
end

--- Whatever a handler puts in a header, the response cannot be split.
function T.cannot_be_made_to_split_a_response()
  local sent = {}
  local client = {
    send = function(_, data) sent[#sent + 1] = data return #data end,
  }
  local socket = { gettime = function() return 0 end }
  server.write_response(client, {
    status = 200,
    headers = {
      ["X-Ok"] = "fine\r\nX-Evil: yes",
      ["Bad Name"] = "dropped",
      ["X-List"] = { "one", "two" },
    },
    body = "hi",
  }, { server_header = false, chunk_bytes = 1024 }, 10, false, socket)

  local text = table.concat(sent)
  -- The CR and LF are dropped, so what was meant to be a second header is
  -- just more of the first one's value.
  assert(not text:find("\r\nX-Evil", 1, true))
  assert(text:find("X-Ok: fineX-Evil: yes", 1, true))
  assert(not text:find("Bad Name", 1, true))
  assert(text:find("X-List: one\r\nX-List: two", 1, true))
  assert(text:find("Content-Length: 2", 1, true))
end

-- Requests and URLs ----------------------------------------------------------------

function T.splits_a_target_into_its_parts()
  local req = make("GET", "/blog/a%20b?tag=lua&tag=web&q=1#here")
  assert(req.path == "/blog/a b")
  assert(req.raw_path == "/blog/a%20b")
  assert(req.search == "?tag=lua&tag=web&q=1")
  assert(req.query.q == "1")
  assert(req.query.tag[2] == "web", "a repeated key is a list")
end

function T.normalises_a_path_without_letting_it_climb_out()
  assert(url.normalize("/a/b/../c") == "/a/c")
  assert(url.normalize("/../../etc/passwd") == "/etc/passwd")
  assert(url.normalize("//a///b/") == "/a/b")
  assert(url.normalize("/a/./b") == "/a/b")
end

--- A Host header is attacker-controlled in shape, if not in value.
function T.replaces_a_host_that_is_not_a_host()
  assert(make("GET", "/", { host = "example.test:8080" }).host == "example.test:8080")
  local bad = make("GET", "/", { host = "evil.test/path" }, { default_host = "safe.test" })
  assert(bad.host == "safe.test")
  assert(make("GET", "/", { host = "a b" }, { default_host = "safe.test" }).host == "safe.test")
end

function T.honours_the_forwarded_headers_only_when_told_to()
  local headers = {
    host = "internal",
    ["x-forwarded-proto"] = "https",
    ["x-forwarded-host"] = "public.test",
    ["x-forwarded-for"] = "203.0.113.1, 10.0.0.1",
  }
  local untrusted = make("GET", "/", headers, {})
  assert(untrusted.scheme == "http")
  assert(untrusted.host == "internal")

  local trusted = make("GET", "/", headers, {
    trust_forwarded = true, address_header = "x-forwarded-for", xff_depth = 1,
  })
  assert(trusted.scheme == "https")
  assert(trusted.host == "public.test")
  assert(trusted.origin == "https://public.test")
  -- One hop from the right is the address the proxy saw.
  assert(trusted.ip == "10.0.0.1")
end

function T.reads_a_form_or_a_json_body()
  local form = request.new({ method = "POST", target = "/", headers = {
    host = "x", ["content-type"] = "application/x-www-form-urlencoded" },
    body = "a=1&b=two+words" }, {})
  assert(form:form().b == "two words")

  local json_body = request.new({ method = "POST", target = "/", headers = {
    host = "x", ["content-type"] = "application/json" }, body = '{"a":1}' }, {})
  assert(json_body:form().a == 1)
  assert(json_body:json().a == 1)
end

-- The router -----------------------------------------------------------------------

function T.matches_in_declaration_order_and_declining_passes_on()
  local router = router_lib.new()
  local seen = {}
  router:get("/a", function() seen[#seen + 1] = "first" return nil end)
  router:get("/a", function() seen[#seen + 1] = "second" return response.text("ok") end)
  local res = router:dispatch(make("GET", "/a"))
  assert(res.body == "ok")
  assert(table.concat(seen, ",") == "first,second")
end

function T.captures_parameters_and_the_rest_of_a_path()
  local router = router_lib.new()
  router:get("/blog/:slug.md", function(_, params) return response.text(params.slug) end)
  router:get("/files/*rest", function(_, params) return response.text(params.rest) end)
  assert(router:dispatch(make("GET", "/blog/why-lua.md")).body == "why-lua")
  assert(router:dispatch(make("GET", "/files/a/b/c")).body == "a/b/c")
end

function T.answers_405_with_the_methods_there_are()
  local router = router_lib.new()
  router:get("/thing", function() return response.text("ok") end)
  router:post("/thing", function() return response.text("made") end)
  local res = router:dispatch(make("DELETE", "/thing"))
  assert(res.status == 405)
  assert(res.headers["Allow"] == "GET, HEAD, POST")
  -- HEAD is served by the GET route.
  assert(router:dispatch(make("HEAD", "/thing")).status == 200)
end

function T.middleware_answers_before_the_table()
  local router = router_lib.new()
  router:use(function(req)
    if req.path == "/closed" then return response.text("no", 403) end
  end)
  router:get("/closed", function() return response.text("yes") end)
  assert(router:dispatch(make("GET", "/closed")).status == 403)
end

function T.turns_what_a_handler_returned_into_a_response()
  assert(response.coerce("<p>x</p>").headers["Content-Type"]:find("text/html", 1, true))
  assert(response.coerce({ a = 1 }).headers["Content-Type"]:find("application/json", 1, true))
  assert(response.coerce({ status = 201, body = "made" }).status == 201)
  assert(response.coerce(nil) == nil)
end

-- Static files ---------------------------------------------------------------------

function T.will_not_serve_a_file_outside_its_root()
  local static = static_lib.new({ root = "examples/tranquility/static", version = "v1" })
  assert(static:resolve("/css/app.css"))
  assert(static:resolve("/") == nil)
  -- A `..` is normalised away rather than followed, encoded or not.
  assert(static:serve(make("GET", "/../../lunar/init.lua"), "/../../lunar/init.lua") == nil)
  assert(static:serve(make("GET", "/%2e%2e/%2e%2e/etc/passwd"), "/%2e%2e/%2e%2e/etc/passwd") == nil)
  -- A dotfile is never served.
  assert(static:resolve("/.env") == nil)
  assert(static:resolve("/a/.git/config") == nil)
end

-- The headers ----------------------------------------------------------------------

function T.hashes_an_inline_script_the_way_a_browser_does()
  assert(security.hash_source("abc")
    == "'sha256-ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0='")
end

function T.locks_down_a_document_and_a_file_differently()
  local headers = security.new({})
  local page = headers:apply({ status = 200, headers = {
    ["Content-Type"] = "text/html; charset=utf-8" } }, make())
  assert(page.headers["Content-Security-Policy"]:find("default-src 'none'", 1, true))
  assert(page.headers["Permissions-Policy"]:find("camera=()", 1, true))
  assert(page.headers["X-Frame-Options"] == "SAMEORIGIN")

  local file = headers:apply({ status = 200, headers = {
    ["Content-Type"] = "text/css" } }, make())
  assert(file.headers["Content-Security-Policy"] == "default-src 'none'; frame-ancestors 'none'; sandbox")
  assert(file.headers["Permissions-Policy"] == nil)
end

function T.widens_one_directive_without_rewriting_the_policy()
  local headers = security.new({ extra = {
    ["img-src"] = { "https://images.test" },
    ["frame-src"] = { "https://embed.test" },
  } })
  local policy = headers.document_policy
  assert(policy:find("img-src 'self' data: https://images.test", 1, true))
  assert(policy:find("frame-src https://embed.test", 1, true))
  assert(not policy:find("frame-src 'none'", 1, true))
end

function T.sends_hsts_only_over_tls()
  local headers = security.new({ hsts_max_age = 600 })
  local html = { status = 200, headers = { ["Content-Type"] = "text/html" } }
  assert(headers:apply(html, make()).headers["Strict-Transport-Security"] == nil)

  local secure = make("GET", "/", { ["x-forwarded-proto"] = "https" },
    { trust_forwarded = true })
  assert(security.new({ hsts_max_age = 600 }):apply(
    { status = 200, headers = { ["Content-Type"] = "text/html" } }, secure)
    .headers["Strict-Transport-Security"] == "max-age=600; includeSubDomains")
end

function T.never_overwrites_a_header_a_handler_set()
  local res = security.new({}):apply({ status = 200, headers = {
    ["Content-Type"] = "text/html",
    ["Content-Security-Policy"] = "default-src 'self'",
  } }, make())
  assert(res.headers["Content-Security-Policy"] == "default-src 'self'")
end

-- Rate limiting --------------------------------------------------------------------

local function limiter(classes, extra)
  local clock = { now = 1000 }
  local options = { classes = classes, now = function() return clock.now end }
  for key, value in pairs(extra or {}) do options[key] = value end
  return ratelimit.new(options), clock
end

function T.spends_a_burst_then_refills()
  local limit, clock = limiter({ page = { capacity = 3, per_second = 1 } })
  for _ = 1, 3 do assert(limit:take("1.2.3.4", "page")) end
  local ok, retry_after = limit:take("1.2.3.4", "page")
  assert(ok == false and retry_after == 1)

  clock.now = clock.now + 2
  assert(limit:take("1.2.3.4", "page"))
  assert(limit:take("1.2.3.4", "page"))
  assert(limit:take("1.2.3.4", "page") == false)

  clock.now = clock.now + 10000
  for _ = 1, 3 do assert(limit:take("1.2.3.4", "page")) end
  assert(limit:take("1.2.3.4", "page") == false, "it never refills past the burst")
end

function T.keeps_addresses_and_classes_apart()
  local limit = limiter({
    page = { capacity = 1, per_second = 1 },
    asset = { capacity = 2, per_second = 1 },
  })
  assert(limit:take("1.2.3.4", "page"))
  assert(limit:take("1.2.3.4", "page") == false)
  assert(limit:take("5.6.7.8", "page"), "another address has its own budget")
  assert(limit:take("1.2.3.4", "asset"), "and so does another class")
end

--- The table must not grow with the number of addresses seen: a flood from a
-- wide range is exactly what this is for.
function T.bounds_what_it_remembers()
  local limit, clock = limiter({ page = { capacity = 2, per_second = 0.001 } },
    { max_keys = 16, idle_seconds = 5 })
  for index = 1, 500 do
    limit:take("10.0.0." .. index, "page")
    limit:take("10.0.0." .. index, "page")
    clock.now = clock.now + 1
  end
  assert(limit.count <= 16, "remembered " .. limit.count .. " addresses")
end

function T.classifies_by_method_and_path_shape()
  assert(ratelimit.classify(make("GET", "/blog/why-lua")) == "page")
  assert(ratelimit.classify(make("GET", "/")) == "page")
  assert(ratelimit.classify(make("GET", "/css/app.css")) == "asset")
  assert(ratelimit.classify(make("GET", "/_lunar/moonlight.lua")) == "asset")
  assert(ratelimit.classify(make("GET", "/images/a.avif")) == "asset")
  assert(ratelimit.classify(make("POST", "/contact")) == "write")
  assert(ratelimit.classify(make("DELETE", "/css/app.css")) == "write")
end

function T.lets_an_exempt_or_unknown_address_through()
  local limit = limiter({ page = { capacity = 1, per_second = 1 } },
    { exempt = { "127.0.0.1" } })
  for _ = 1, 20 do
    assert(limit:take("127.0.0.1", "page"))
    assert(limit:take(nil, "page"))
  end
end

return T
