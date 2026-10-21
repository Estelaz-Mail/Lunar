--- An HTTP/1.1 server.
--
-- LuaSocket provides the socket syscalls and nothing else: the protocol, the
-- connection scheduling and the timeouts are here. Every connection runs in
-- its own coroutine, a coroutine yields whenever a socket would block, and the
-- loop uses `socket.select` to resume only the ones that can make progress.
-- One OS thread serves many keep-alive connections, which is what a
-- server-rendered app behind a proxy needs.
--
-- There is no TLS. Put a proxy in front and let it pass the real scheme and
-- host through the forwarded headers.

local request_lib = require("lunar.http.request")
local response_lib = require("lunar.http.response")
local util = require("lunar.core.util")

local server = {}

local DEFAULTS = {
  host = "0.0.0.0",
  port = 3000,
  backlog = 128,
  keepalive_timeout = 15,
  read_timeout = 20,
  write_timeout = 30,
  max_header_bytes = 32 * 1024,
  max_body_bytes = 1024 * 1024,
  max_requests_per_connection = 200,
  chunk_bytes = 64 * 1024,
  -- One process, one thread: the ceiling is on how many sockets the loop
  -- carries. Past it a connection is closed on accept rather than queued, so a
  -- client holding a thousand idle sockets cannot keep the loop from serving
  -- everyone else.
  max_connections = 512,
  max_connections_per_ip = 0,
  server_header = "lunar",
}

local WANT_READ, WANT_WRITE = "read", "write"

-- Reading --------------------------------------------------------------------

local Reader = {}
Reader.__index = Reader

local function new_reader(client, limits, socket)
  return setmetatable({
    client = client, buffer = "", position = 1, limits = limits, socket = socket,
  }, Reader)
end

function Reader:set_deadline(seconds)
  self.deadline = seconds and (self.socket.gettime() + seconds) or nil
end

function Reader:expired()
  return self.deadline ~= nil and self.socket.gettime() > self.deadline
end

function Reader:fill()
  while true do
    if self:expired() then return nil, "timeout" end
    local chunk, err, partial = self.client:receive(self.limits.chunk_bytes)
    if chunk or (partial and #partial > 0) then
      self.buffer = self.buffer:sub(self.position) .. (chunk or partial)
      self.position = 1
      return true
    end
    if err == "timeout" then
      coroutine.yield(WANT_READ)
    else
      return nil, err or "closed"
    end
  end
end

function Reader:line()
  while true do
    local from, to = self.buffer:find("\r?\n", self.position)
    if from then
      local line = self.buffer:sub(self.position, from - 1)
      self.position = to + 1
      return line
    end
    if #self.buffer - self.position + 1 > self.limits.max_header_bytes then
      return nil, "header too large"
    end
    local ok, err = self:fill()
    if not ok then return nil, err end
  end
end

function Reader:bytes(count)
  while #self.buffer - self.position + 1 < count do
    local ok, err = self:fill()
    if not ok then return nil, err end
  end
  local out = self.buffer:sub(self.position, self.position + count - 1)
  self.position = self.position + count
  return out
end

-- Writing --------------------------------------------------------------------

local function send_all(client, data, deadline, socket)
  local sent, total = 0, #data
  while sent < total do
    if socket.gettime() > deadline then return nil, "timeout" end
    local ok, err, last = client:send(data, sent + 1)
    if ok then
      sent = ok
    elseif err == "timeout" then
      sent = last or sent
      coroutine.yield(WANT_WRITE)
    else
      return nil, err or "closed"
    end
  end
  return true
end

-- A header name must be a token and a value must not contain CR, LF or NUL.
-- Nothing should reach here carrying one, so this is the backstop that makes
-- response splitting impossible whatever a handler puts in a header.
local function header_name_ok(name)
  return type(name) == "string" and name:match("^[%w!#%$%%&'%*%+%-%.%^_`|~]+$") ~= nil
end

local function header_value(value)
  return (tostring(value):gsub("[\0\r\n]", ""))
end

local function write_response(client, res, options, deadline, head_only, socket)
  local status = math.floor(tonumber(res.status) or 200)
  if status < 100 or status > 599 then status = 500 end

  local lines = { string.format("HTTP/1.1 %d %s", status, response_lib.status_text(status)) }
  local has_length = false
  local names = {}
  for name in pairs(res.headers or {}) do names[#names + 1] = name end
  table.sort(names)

  for _, name in ipairs(names) do
    local value = res.headers[name]
    local lowered = type(name) == "string" and name:lower() or ""
    -- `Connection` and `Date` are written below, from the connection's own
    -- state: a copy carried on the response would be a second, contradicting
    -- header, and two Connection headers are how a keep-alive desync starts.
    if lowered == "connection" or lowered == "date" then
      if lowered == "connection" then res.connection = res.connection or value end
    elseif not header_name_ok(name) then
      io.stderr:write("lunar: dropped a header with an invalid name: ", tostring(name), "\n")
    else
      if type(value) == "table" then
        for _, item in ipairs(value) do lines[#lines + 1] = name .. ": " .. header_value(item) end
      else
        lines[#lines + 1] = name .. ": " .. header_value(value)
      end
      if lowered == "content-length" then has_length = true end
    end
  end

  local file = res.file
  if not has_length then
    local length = res.content_length or (file and file.length) or #(res.body or "")
    lines[#lines + 1] = "Content-Length: " .. tostring(length)
  end
  lines[#lines + 1] = "Date: " .. os.date("!%a, %d %b %Y %H:%M:%S GMT")
  if options.server_header then lines[#lines + 1] = "Server: " .. options.server_header end
  lines[#lines + 1] = "Connection: " .. header_value(res.connection or "keep-alive")
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""

  local ok, err = send_all(client, table.concat(lines, "\r\n"), deadline, socket)
  if not ok then return nil, err end
  if head_only or status == 204 or status == 304 then return true end

  if file then
    local handle = io.open(file.path, "rb")
    if not handle then return nil, "the file vanished" end
    if file.offset and file.offset > 0 then handle:seek("set", file.offset) end
    local remaining = file.length
    while remaining > 0 do
      local chunk = handle:read(math.min(options.chunk_bytes, remaining))
      if not chunk or #chunk == 0 then break end
      remaining = remaining - #chunk
      local sent, send_err = send_all(client, chunk, deadline, socket)
      if not sent then
        handle:close()
        return nil, send_err
      end
    end
    handle:close()
    return true
  end

  if #(res.body or "") > 0 then
    return send_all(client, res.body, deadline, socket)
  end
  return true
end

-- Parsing --------------------------------------------------------------------

local function parse_request_line(line)
  local method, target, version = line:match("^(%u+)%s+(%S+)%s+(HTTP/%d%.%d)$")
  if not method then return nil, "malformed request line" end
  return { method = method, target = target, version = version }
end

--- A target may not carry a control character, raw or percent-encoded.
--
-- `%S+` above already keeps CR, LF, space and tab out of the raw target, but
-- the path is percent-decoded before a handler sees it, so `%0d%0a` would
-- arrive as a real CRLF and from there into a response header. The decoded
-- form is checked here because this is the last place that can answer 400.
local function target_is_safe(target)
  if target:find("[\0-\31\127]") then return false end
  for hex in target:gmatch("%%(%x%x)") do
    local byte = tonumber(hex, 16)
    if byte <= 0x1f or byte == 0x7f then return false end
  end
  return true
end

local function read_headers(reader, limits)
  local headers = {}
  local total = 0
  local last_name
  while true do
    local line, err = reader:line()
    if not line then return nil, err end
    if line == "" then return headers end
    total = total + #line + 2
    if total > limits.max_header_bytes then return nil, "header too large" end
    if line:match("^[ \t]") and last_name then
      headers[last_name] = headers[last_name] .. " " .. util.trim(line)
    else
      local name, value = line:match("^([^:]+):%s*(.-)%s*$")
      if not name then return nil, "malformed header" end
      name = name:lower()
      headers[name] = headers[name] and (headers[name] .. ", " .. value) or value
      last_name = name
    end
  end
end

--- RFC 9112 framing. A request whose body length is ambiguous is refused
-- rather than guessed at: a server that guesses differently from the proxy in
-- front of it is how a request gets smuggled past that proxy.
local function check_framing(headers)
  local encoding = headers["transfer-encoding"]
  local length = headers["content-length"]
  if encoding then
    if length then return 400, "both transfer-encoding and content-length" end
    if util.trim(encoding):lower() ~= "chunked" then
      return 501, "unsupported transfer-encoding"
    end
  elseif length then
    -- Two Content-Lengths arrive joined with ", ", which is not a number.
    -- Only digits pass, which also rules out "0x10", a sign and an exponent.
    if not length:match("^%s*%d+%s*$") then return 400, "malformed content-length" end
  end
  return nil
end

local function body_reader(reader, headers, limits)
  local encoding = (headers["transfer-encoding"] or ""):lower()
  if encoding:find("chunked", 1, true) then
    return function()
      local parts, total = {}, 0
      while true do
        local line = reader:line()
        if not line then return nil end
        local size = tonumber((line:match("^(%x+)")) or "", 16)
        if not size then return nil end
        if size == 0 then
          while true do
            local trailer = reader:line()
            if not trailer or trailer == "" then break end
          end
          return table.concat(parts)
        end
        total = total + size
        if total > limits.max_body_bytes then return nil end
        local chunk = reader:bytes(size)
        if not chunk then return nil end
        parts[#parts + 1] = chunk
        reader:bytes(2)
      end
    end
  end

  local length = tonumber(headers["content-length"] or "0") or 0
  if length <= 0 then return nil end
  if length > limits.max_body_bytes then
    return function() return nil, "too large" end, length
  end
  return function() return reader:bytes(length) end, length
end

-- Connections ----------------------------------------------------------------

local function error_response(status, message)
  local res = response_lib.text(string.format("%d %s\n%s", status,
    response_lib.status_text(status), message and (message .. "\n") or ""), status)
  res.connection = "close"
  return res
end

local function serve_connection(client, handler, options, socket)
  client:setoption("tcp-nodelay", true)
  client:settimeout(0)
  local reader = new_reader(client, options, socket)
  local peer = client:getpeername()
  local served = 0

  local function fail(status, message)
    write_response(client, error_response(status, message), options,
      socket.gettime() + options.write_timeout, false, socket)
  end

  while true do
    served = served + 1
    reader:set_deadline(served == 1 and options.read_timeout or options.keepalive_timeout)

    local line = reader:line()
    if not line then return end
    while line == "" do
      line = reader:line()
      if not line then return end
    end

    reader:set_deadline(options.read_timeout)
    local head, head_err = parse_request_line(line)
    if not head then return fail(400, head_err) end
    if #head.target > 8190 then return fail(414) end
    if not target_is_safe(head.target) then return fail(400, "malformed request target") end

    local headers, headers_err = read_headers(reader, options)
    if not headers then
      return fail(headers_err == "header too large" and 431 or 400, headers_err)
    end

    local framing_status, framing_err = check_framing(headers)
    if framing_status then return fail(framing_status, framing_err) end

    local read_body_fn, declared = body_reader(reader, headers, options)
    if declared and declared > options.max_body_bytes then return fail(413) end

    -- A body that cannot be read to its end leaves the connection at an
    -- unknown offset, so what follows is not a request and the connection is
    -- not reused.
    local body_complete = true
    if read_body_fn then
      local read_one = read_body_fn
      read_body_fn = function()
        local chunk, err = read_one()
        if not chunk then body_complete = false end
        return chunk, err
      end
    end

    local req = request_lib.new({
      method = head.method, target = head.target, version = head.version,
      headers = headers, ip = peer, read_body_fn = read_body_fn,
    }, options)

    local ok, res = pcall(handler, req)
    if not ok then
      io.stderr:write("lunar: request failed: ", tostring(res), "\n")
      res = error_response(500)
    end
    if type(res) ~= "table" then
      res = error_response(500, "the handler returned no response")
    end

    local wants_close = (headers["connection"] or ""):lower():find("close", 1, true) ~= nil
      or head.version == "HTTP/1.0"
      or served >= options.max_requests_per_connection
      or res.close
    if wants_close then res.connection = "close" end

    -- A body the handler never read would be parsed as the next request line.
    if read_body_fn and req.body == nil then
      if not pcall(function() req:read_body() end) then body_complete = false end
    end
    if not body_complete then
      wants_close = true
      res.connection = "close"
    end

    local sent, send_err = write_response(client, res, options,
      socket.gettime() + options.write_timeout, req:is_head(), socket)
    if not sent then
      if send_err ~= "closed" then
        io.stderr:write("lunar: send failed: ", tostring(send_err), "\n")
      end
      return
    end

    if wants_close then return end
  end
end

--- Starts the accept loop and blocks until `stop()` is called, which is what
-- makes a container's SIGTERM a clean exit.
function server.serve(options)
  local ok, socket = pcall(require, "socket")
  if not ok then
    error("lunar: serving needs LuaSocket (luarocks install luasocket), "
      .. "everything else runs without it", 0)
  end

  options = util.merge(DEFAULTS, options or {})
  local handler = assert(options.handler, "lunar: serve needs a handler")

  local master = assert(socket.bind(options.host, options.port, options.backlog))
  master:settimeout(0)
  master:setoption("reuseaddr", true)

  local running = true
  local connections = {}
  local open_connections = 0
  local per_ip = {}

  local function stop() running = false end
  if options.on_ready then options.on_ready({ stop = stop, socket = master }) end

  local function forget(entry)
    if not connections[entry.client] then return end
    connections[entry.client] = nil
    open_connections = open_connections - 1
    if entry.address and per_ip[entry.address] then
      local remaining = per_ip[entry.address] - 1
      per_ip[entry.address] = remaining > 0 and remaining or nil
    end
  end

  local function resume(entry)
    local resumed, kind = coroutine.resume(entry.co)
    if not resumed then
      io.stderr:write("lunar: connection failed: ", tostring(kind), "\n")
    end
    if coroutine.status(entry.co) == "dead" then return forget(entry) end
    entry.want = (kind == WANT_WRITE) and WANT_WRITE or WANT_READ
  end

  local function spawn(client, address)
    local co = coroutine.create(function()
      local succeeded, err = pcall(serve_connection, client, handler, options, socket)
      if not succeeded then
        io.stderr:write("lunar: connection failed: ", tostring(err), "\n")
      end
      client:close()
    end)
    connections[client] = { co = co, want = WANT_READ, client = client, address = address }
    open_connections = open_connections + 1
    if address then per_ip[address] = (per_ip[address] or 0) + 1 end
    return connections[client]
  end

  while running do
    local read_set, write_set = { master }, {}
    for client, entry in pairs(connections) do
      if entry.want == WANT_WRITE then
        write_set[#write_set + 1] = client
      else
        read_set[#read_set + 1] = client
      end
    end

    local readable, writable = socket.select(read_set, write_set, 0.5)

    for _, ready in ipairs(readable) do
      if ready == master then
        local client = master:accept()
        while client do
          local entry = connections[client]
          if entry then
            resume(entry)
          else
            local address = client:getpeername()
            local cap = options.max_connections_per_ip
            local over_ip = cap > 0 and address and (per_ip[address] or 0) >= cap
            if open_connections >= options.max_connections or over_ip then
              pcall(function() client:close() end)
            else
              resume(spawn(client, address))
            end
          end
          client = master:accept()
        end
      else
        local entry = connections[ready]
        if entry then resume(entry) end
      end
    end

    for _, ready in ipairs(writable) do
      local entry = connections[ready]
      if entry then resume(entry) end
    end
  end

  for client in pairs(connections) do pcall(function() client:close() end) end
  master:close()
end

server.defaults = DEFAULTS

-- Exported for the specs: the three places the protocol is enforced rather
-- than parsed, which are the ones a regression would be silent in.
server.target_is_safe = target_is_safe
server.check_framing = check_framing
server.write_response = write_response

return server
