local bundle = require("lunar.site.bundle")
local compiler = require("lunar.compiler")
local fs = require("lunar.core.fs")
local request = require("lunar.http.request")
local util = require("lunar.core.util")

local bench = {}

local function clock()
  local ok, socket = pcall(require, "socket")
  if ok and socket.gettime then return socket.gettime end
  return os.clock
end

local now = clock()

local function measure(seconds, fn)
  for _ = 1, 3 do fn() end
  local started = now()
  local count = 0
  local elapsed = 0
  repeat
    fn()
    count = count + 1
    elapsed = now() - started
  until elapsed >= seconds
  return count / elapsed, elapsed, count
end

local function percentiles(times)
  table.sort(times)
  local function at(fraction)
    return times[math.max(1, math.min(#times, math.ceil(#times * fraction)))]
  end
  return at(0.5), at(0.95), at(0.99), times[#times]
end

function bench.run(root, options)
  options = options or {}
  local lunar = require("lunar")
  local app = lunar.app({ root = root, dev = false, version = "bench",
    rate_limit = { enabled = false } })

  io.write(string.format("lunar %s — %s, %s\n\n", lunar.VERSION, _VERSION,
    (io.popen and (function()
      local pipe = io.popen("uname -sm 2>/dev/null")
      if not pipe then return "unknown machine" end
      local line = util.trim(pipe:read("l") or "")
      pipe:close()
      return line ~= "" and line or "unknown machine"
    end)()) or "unknown machine"))

  local components = {}
  for _, relative in ipairs(fs.files(root)) do
    if relative:match("%.lunar$") then components[#components + 1] = fs.join(root, relative) end
  end

  local sources = {}
  for _, path in ipairs(components) do sources[path] = assert(util.read_file(path)) end

  local started = now()
  for _, path in ipairs(components) do
    compiler.compile(sources[path], { path = path })
  end
  local compile_time = now() - started
  io.write(string.format("compiling\n  %d components in %.0f ms, %.1f ms each\n\n",
    #components, compile_time * 1000, compile_time * 1000 / #components))

  io.write("rendering, in process\n")
  local handler = app:handler()
  local routes = {}
  for _, route in ipairs(app.routes) do
    if route.page then routes[#routes + 1] = route.id:gsub("%[%.%.%..-%]", "x"):gsub("%[.-%]", "why-lua") end
  end
  table.sort(routes)

  local seconds = options.seconds or 2
  for _, path in ipairs(routes) do
    local function once()
      local req = request.new({ method = "GET", target = path,
        headers = { host = "bench.local" } }, {})
      req.ip = "203.0.113.1"
      return handler(req)
    end
    local probe = once()
    if probe.status ~= 200 then
      io.write(string.format("  %-14s skipped: the route answered %d\n", path, probe.status))
      goto continue
    end
    local rate, elapsed, count = measure(seconds, once)

    local times = {}
    for _ = 1, math.min(2000, math.max(200, math.floor(rate))) do
      local before = now()
      once()
      times[#times + 1] = (now() - before) * 1000
    end
    local p50, p95, p99, worst = percentiles(times)

    collectgarbage("collect")
    collectgarbage("stop")
    local before_memory = collectgarbage("count")
    for _ = 1, 100 do once() end
    local per_page = (collectgarbage("count") - before_memory) / 100
    collectgarbage("restart")
    collectgarbage("collect")

    io.write(string.format(
      "  %-14s %7.0f pages/s   %.2f ms median, %.2f p95, %.2f p99, %.2f worst"
      .. "   %d bytes   %.0f KB allocated\n",
      path, rate, p50, p95, p99, worst, #(probe.body or ""), per_page))
    local _ = (elapsed and count)
    ::continue::
  end

  bench.takeover(app, routes, seconds)

  io.write("\nwhat the browser downloads\n")
  local moonlight = assert(bundle.build(app))
  local runtime_size = 0
  for _, name in ipairs({ "boot.ts", "bridge.ts", "lua54.wasm" }) do
    runtime_size = runtime_size + #(util.read_file(fs.join(app.framework, "static", "runtime", name)) or "")
  end
  io.write(string.format("  moonlight bundle   %6.1f KB\n", #moonlight / 1024))
  io.write(string.format("  Lua 5.4 runtime    %6.1f KB\n", runtime_size / 1024))
  io.write(string.format("  both              %6.1f KB, uncompressed\n",
    (#moonlight + runtime_size) / 1024))

  local server = assert(bundle.server(app))
  io.write(string.format("\nwhat an edge runtime gets\n  frozen app         %6.1f KB\n",
    #server / 1024))

  io.write("\nOne core, no socket in the way, no cache: a page here is every probe,\n"
    .. "every component and the whole document, rendered from nothing.\n")
end

local function table_dom()
  local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/lunar/bench%.lua$")
  if not root then return nil end
  local chunk = loadfile(root .. "/spec/mockdom.lua")
  if not chunk then return nil end
  local ok, mock = pcall(chunk)
  return ok and mock or nil
end

function bench.takeover(app, routes, seconds)
  local mock = table_dom()
  io.write("\ntaking the server's page over, against a DOM of Lua tables\n")
  if not mock then
    io.write("  skipped: this needs spec/mockdom.lua, which an installed Lunar has not got\n")
    return
  end

  local component = require("lunar.runtime.component")
  local moonlight = require("lunar.site.moonlight")
  local render = require("lunar.site.render")
  local routes_lib = require("lunar.site.routes")
  local slice = math.max(0.3, (seconds or 2) / 3)

  for _, path in ipairs(routes) do
    local route, params = routes_lib.match(app.routes, path)
    if route then
      local req = request.new({ method = "GET", target = path,
        headers = { host = "bench.local" } }, {})
      req.ip = "203.0.113.1"
      local event = render.event(req, route, params)
      local drawn = render.drawn(render.probe_chain(app, route, event))
      local defs, data = {}, {}
      for index, level in ipairs(drawn) do
        defs[index] = app:component(level.component)
        data[index] = level.data
      end
      local markup = render.chain(defs, data, { params = params })

      local rebuilt
      local parse_rate = measure(slice, function() mock.parse(markup) end)
      local claim_rate = measure(slice, function()
        local dom = mock.parse(markup)
        moonlight.mount_chain(defs, data, dom.body, dom, { params = params, hydrate = true,
          on_rebuild = function(why) rebuilt = why end })
      end)
      local rebuild_rate = measure(slice, function()
        local dom = mock.parse(markup)
        moonlight.mount_chain(defs, data, dom.body, dom, { params = params })
      end)

      local parse_ms = 1000 / parse_rate
      io.write(string.format("  %-14s claim %.2f ms   rebuild %.2f ms%s\n",
        path, 1000 / claim_rate - parse_ms, 1000 / rebuild_rate - parse_ms,
        rebuilt and ("   did not claim: " .. tostring(rebuilt)) or ""))
    end
  end

  local def = compiler.load([[<script>
  count = 0
</script>
<p>{count}</p>]], { path = "bench.lunar" })
  local dom = mock.new()
  local instance = component.mount(def, dom.body, {}, { dom = dom })
  local value = 0
  local rate = measure(slice, function()
    value = value + 1
    instance.scope.count = value
  end)
  io.write(string.format("  %-14s %.1f us per patch, one text node from one signal\n",
    "patching", 1e6 / rate))
  io.write("\n  In a table DOM a node costs a table, so claiming is not the faster of\n"
    .. "  the two here and is not meant to look like it: what it buys is the node\n"
    .. "  itself — the focus, the text a visitor already typed, the image already\n"
    .. "  decoded. In a browser a created node also costs layout and paint, which\n"
    .. "  is the part this cannot measure.\n")
end

function bench.http(url, options)
  options = options or {}
  local ok, socket = pcall(require, "socket")
  if not ok then
    io.stderr:write("lunar: bench --http needs LuaSocket\n")
    os.exit(1)
  end

  local host, port, path = url:match("^http://([^/:]+):?(%d*)(/.*)$")
  if not host then
    io.stderr:write("lunar: bench --http wants a URL like http://127.0.0.1:3000/\n")
    os.exit(1)
  end
  port = tonumber(port ~= "" and port or "80")
  path = path ~= "" and path or "/"

  local count = options.connections or 32
  local seconds = options.seconds or 5
  local message = string.format(
    "GET %s HTTP/1.1\r\nHost: %s\r\nAccept: text/html\r\nConnection: keep-alive\r\n\r\n",
    path, host)

  local clients, pending = {}, {}
  for index = 1, count do
    local client = assert(socket.connect(host, port))
    client:settimeout(0)
    clients[index] = client
    pending[client] = { buffer = "", started = socket.gettime() }
    client:send(message)
  end

  local done, failed = 0, 0
  local times = {}
  local started = socket.gettime()
  while socket.gettime() - started < seconds do
    local readable = socket.select(clients, nil, 0.5)
    for _, client in ipairs(readable) do
      local state = pending[client]
      local chunk, err, partial = client:receive(65536)
      local data = chunk or partial
      if (not data or data == "") and err and err ~= "timeout" then
        failed = failed + 1
        pcall(function() client:close() end)
        local fresh = socket.connect(host, port)
        if fresh then
          fresh:settimeout(0)
          pending[fresh] = { buffer = "", started = socket.gettime() }
          pending[client] = nil
          for index, candidate in ipairs(clients) do
            if candidate == client then clients[index] = fresh break end
          end
          fresh:send(message)
        end
      elseif data and data ~= "" then
        state.buffer = state.buffer .. data
        local head_end = state.buffer:find("\r\n\r\n", 1, true)
        local length = head_end and tonumber(state.buffer:match("[Cc]ontent%-[Ll]ength: (%d+)") or "")
        if head_end and length and #state.buffer >= head_end + 3 + length then
          done = done + 1
          times[#times + 1] = (socket.gettime() - state.started) * 1000
          state.buffer = state.buffer:sub(head_end + 4 + length)
          state.started = socket.gettime()
          client:send(message)
        end
      end
    end
  end
  local elapsed = socket.gettime() - started
  for _, client in ipairs(clients) do client:close() end

  local p50, p95, p99, worst = percentiles(times)
  io.write(string.format("over HTTP, %d keep-alive connections, %.0fs\n", count, elapsed))
  io.write(string.format("  %s\n", url))
  io.write(string.format("  %.0f requests/s   %.2f ms median, %.2f p95, %.2f p99, %.2f worst\n",
    done / elapsed, p50, p95, p99, worst))
  if failed > 0 then
    io.write(string.format("  %d connections closed by the server and reopened\n", failed))
  end
  io.write("\nThe client is one process and one loop too, so this is both sides on\n"
    .. "the same machine: the number is a floor, not a ceiling.\n")
end

return bench
