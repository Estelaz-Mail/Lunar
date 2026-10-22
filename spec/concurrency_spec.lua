local server = require("lunar.http.server")

local T = {}

local function new_socket_library()
  local lib = { time = 1000, pending = {}, closed = 0 }

  function lib.gettime() return lib.time end
  function lib.advance(seconds) lib.time = lib.time + seconds end

  local Socket = {}
  Socket.__index = Socket

  function Socket:settimeout() end
  function Socket:setoption() return true end
  function Socket:getpeername() return self.address end
  function Socket:getsockname() return "127.0.0.1", self.port end

  function Socket:receive(count)
    if self.inbox == "" then
      if self.half_closed then return nil, "closed" end
      return nil, "timeout"
    end
    local chunk = self.inbox:sub(1, count)
    self.inbox = self.inbox:sub(#chunk + 1)
    return chunk
  end

  function Socket:send(data, from)
    if self.closed then return nil, "closed" end
    local remaining = data:sub(from or 1)
    local limit = self.send_limit or #remaining
    local taken = remaining:sub(1, limit)
    self.outbox = self.outbox .. taken
    local sent = (from or 1) - 1 + #taken
    if #taken < #remaining then return nil, "timeout", sent end
    return sent
  end

  function Socket:close() self.closed = true; lib.closed = lib.closed + 1 end

  function lib.connect(request, options)
    options = options or {}
    local client = setmetatable({
      inbox = request or "", outbox = "", address = options.address or "203.0.113.1",
      send_limit = options.send_limit, closed = false,
    }, Socket)
    lib.pending[#lib.pending + 1] = client
    return client
  end

  lib.master = setmetatable({ inbox = "", outbox = "", port = 3000, is_master = true,
    accept = function()
      if #lib.pending == 0 then return nil end
      return table.remove(lib.pending, 1)
    end,
  }, Socket)

  function lib.bind() return lib.master end

  function lib.select(read_set, write_set, _)
    if lib.interrupt then error("interrupted!") end
    if lib.failure then error(lib.failure) end
    local readable, writable = {}, {}
    for _, candidate in ipairs(read_set or {}) do
      if candidate.is_master then
        if #lib.pending > 0 then readable[#readable + 1] = candidate end
      elseif candidate.inbox ~= "" or candidate.half_closed then
        readable[#readable + 1] = candidate
      end
    end
    for _, candidate in ipairs(write_set or {}) do
      writable[#writable + 1] = candidate
    end
    return readable, writable
  end

  return lib
end

local function request_for(path, extra)
  return string.format("GET %s HTTP/1.1\r\nHost: lunar.test\r\n%s\r\n", path, extra or "")
end

local function counting_handler()
  local calls = { n = 0 }
  return function(req)
    calls.n = calls.n + 1
    calls[#calls + 1] = req.path
    return { status = 200, headers = { ["Content-Type"] = "text/plain" },
      body = "answered " .. req.path }
  end, calls
end

local function listener_for(handler, socket, options)
  local merged = { host = "127.0.0.1", port = 3000, handler = handler, socket = socket }
  for key, value in pairs(options or {}) do merged[key] = value end
  return server.listener(merged)
end

local function run(listener, steps)
  for _ = 1, steps or 200 do
    if listener.step(0) == 0 then return end
  end
  error("the loop never came to rest")
end

local function responses_in(client)
  local found = {}
  for status in client.outbox:gmatch("HTTP/1%.1 (%d+)") do found[#found + 1] = status end
  return found
end

function T.serves_many_connections_in_one_loop()
  local socket = new_socket_library()
  local handler, calls = counting_handler()
  local listener = listener_for(handler, socket)

  local clients = {}
  for index = 1, 16 do
    local path = "/page/" .. index
    clients[index] = socket.connect(
      request_for(path) .. request_for(path) .. request_for(path),
      { address = "203.0.113." .. index })
  end

  run(listener)

  assert(calls.n == 48, "every request was handled, got " .. calls.n)
  for index, client in ipairs(clients) do
    local statuses = responses_in(client)
    assert(#statuses == 3, "connection " .. index .. " got " .. #statuses .. " responses")
    for _, status in ipairs(statuses) do assert(status == "200", status) end
    assert(client.outbox:find("answered /page/" .. index, 1, true),
      "connection " .. index .. " got its own answer")
  end
  assert(listener.connections() == 16,
    "and all sixteen are still open: nothing said to close them")
  listener.close()
end

function T.a_slow_client_does_not_hold_up_the_others()
  local socket = new_socket_library()
  local handler, calls = counting_handler()
  local listener = listener_for(handler, socket)

  local message = request_for("/slow")
  local slow = socket.connect(message:sub(1, 1))
  local fast = {}
  for index = 1, 4 do
    fast[index] = socket.connect(request_for("/fast/" .. index),
      { address = "198.51.100." .. index })
  end

  run(listener)

  assert(calls.n == 4, "the four complete requests were answered")
  for index, client in ipairs(fast) do
    assert(client.outbox:find("answered /fast/" .. index, 1, true), index)
  end
  assert(slow.outbox == "", "the slow one is still being waited for")
  assert(listener.connections() == 5, "and it is still open, with the four served ones")

  for position = 2, #message do
    slow.inbox = slow.inbox .. message:sub(position, position)
    listener.step(0)
  end
  run(listener)

  assert(slow.outbox:find("answered /slow", 1, true), "the slow one was answered in the end")
  assert(calls.n == 5)
  listener.close()
end

function T.drops_a_connection_that_stops_talking()
  local socket = new_socket_library()
  local handler = counting_handler()
  local listener = listener_for(handler, socket, { read_timeout = 5 })

  local silent = socket.connect("")
  listener.step(0)
  assert(listener.connections() == 1, "it was accepted")

  socket.advance(4)
  listener.step(0)
  assert(listener.connections() == 1, "and is still being waited for")

  socket.advance(2)
  listener.step(0)
  run(listener)
  assert(listener.connections() == 0, "past the timeout it is dropped")
  assert(silent.closed, "and its socket is closed")
  listener.close()
end

function T.refuses_a_connection_past_the_cap()
  local socket = new_socket_library()
  local handler, calls = counting_handler()
  local listener = listener_for(handler, socket, { max_connections = 2 })

  local idle = { socket.connect(""), socket.connect("") }
  listener.step(0)
  assert(listener.connections() == 2)

  local refused = socket.connect(request_for("/late"))
  run(listener)
  assert(refused.closed, "the connection past the cap was closed")
  assert(calls.n == 0, "and never reached the handler")

  idle[1].half_closed = true
  run(listener)
  assert(listener.connections() == 1)

  local welcome = socket.connect(request_for("/now"))
  run(listener)
  assert(welcome.outbox:find("answered /now", 1, true), "the slot was reused")
  listener.close()
end

function T.refuses_a_second_connection_from_the_same_address()
  local socket = new_socket_library()
  local handler = counting_handler()
  local listener = listener_for(handler, socket, { max_connections_per_ip = 1 })

  local first = socket.connect("", { address = "203.0.113.9" })
  local second = socket.connect(request_for("/x"), { address = "203.0.113.9" })
  local other = socket.connect(request_for("/y"), { address = "203.0.113.10" })
  run(listener)

  assert(not first.closed, "the first one from that address is served")
  assert(second.closed, "the second is not")
  assert(other.outbox:find("answered /y", 1, true), "another address is unaffected")
  listener.close()
end

function T.closes_a_connection_after_its_request_budget()
  local socket = new_socket_library()
  local handler, calls = counting_handler()
  local listener = listener_for(handler, socket, { max_requests_per_connection = 2 })

  local client = socket.connect(request_for("/a") .. request_for("/b") .. request_for("/c"))
  run(listener)

  assert(calls.n == 2, "two requests, not three")
  local statuses = responses_in(client)
  assert(#statuses == 2)
  assert(client.outbox:lower():find("connection: close", 1, true),
    "and the last response said the connection was ending")
  assert(client.closed, "the socket is closed")
  listener.close()
end

function T.writes_a_response_across_as_many_turns_as_it_takes()
  local socket = new_socket_library()
  local body = string.rep("moonlight ", 500)
  local listener = listener_for(function()
    return { status = 200, headers = { ["Content-Type"] = "text/plain" }, body = body }
  end, socket)

  local slow = socket.connect(request_for("/big"), { send_limit = 16 })
  local quick = socket.connect(request_for("/big"), { address = "203.0.113.2" })

  listener.step(0)
  listener.step(0)
  assert(#slow.outbox < #body, "the slow socket is still being written to")

  run(listener, 2000)
  assert(slow.outbox:sub(-#body) == body, "and it got the whole body in the end")
  assert(quick.outbox:sub(-#body) == body, "while the other one was served too")
  listener.close()
end

function T.stops_quietly_when_it_is_interrupted()
  local socket = new_socket_library()
  local handler, calls = counting_handler()
  local listener = listener_for(handler, socket)

  socket.connect(request_for("/before"))
  run(listener)
  assert(calls.n == 1, "it served before the interrupt")

  socket.interrupt = true
  local resumed = listener.step(0)
  assert(resumed == 0, "the interrupted step did nothing")
  assert(listener.running == false, "and the loop stopped")
  assert(listener.interrupted == true, "and said why")
  listener.close()
end

function T.raises_anything_other_than_an_interrupt()
  local socket = new_socket_library()
  local handler = counting_handler()
  local listener = listener_for(handler, socket)

  socket.failure = "bad file descriptor"
  local ok, err = pcall(listener.step, 0)
  assert(ok == false, "the failure was not raised")
  assert(tostring(err):find("bad file descriptor", 1, true), tostring(err))
  assert(listener.running == true, "and the loop was not stopped by it")
  listener.close()
end

return T
