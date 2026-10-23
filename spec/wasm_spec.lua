local compile = require("lunar.wasm.compile")
local encode = require("lunar.wasm.encode")
local module_lib = require("lunar.wasm.module")
local parts_lib = require("lunar.wasm.parts")
local wasm_runtime = require("lunar.runtime.wasm")

local T = {}

local function compile_error(source)
  local ok, err = pcall(compile.chunk, source, { filename = "part.lua" })
  assert(not ok, "this was expected to be refused: " .. source)
  return tostring(err)
end

function T.writes_the_integers_the_way_the_format_asks()
  assert(encode.unsigned(0) == "\x00")
  assert(encode.unsigned(127) == "\x7f")
  assert(encode.unsigned(128) == "\x80\x01")
  assert(encode.unsigned(624485) == "\xe5\x8e\x26")
  assert(encode.signed(0) == "\x00")
  assert(encode.signed(63) == "\x3f")
  assert(encode.signed(64) == "\xc0\x00")
  assert(encode.signed(-1) == "\x7f")
  assert(encode.signed(-123456) == "\xc0\xbb\x78")
  assert(encode.float(1.5) == string.pack("<d", 1.5))
  assert(not pcall(encode.unsigned, -1))
end

function T.builds_a_module_a_runtime_would_accept()
  local builder = module_lib.new()
  local index = builder:add_function({ "f64" }, { "f64" }, {}, "\x20\x00\x20\x00\xa0")
  builder:export_function("twice", index)
  local bytes = builder:encode()

  assert(bytes:sub(1, 8) == "\0asm\1\0\0\0", "the magic and the version lead")
  assert(bytes == "\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x06\x01\x60\x01\x7c\x01\x7c"
    .. "\x03\x02\x01\x00\x07\x09\x01\x05\x74\x77\x69\x63\x65\x00\x00\x0a\x09\x01"
    .. "\x07\x00\x20\x00\x20\x00\xa0\x0b", "the bytes are not what the format says")
end

function T.numbers_the_functions_after_the_imports()
  local builder = module_lib.new()
  local imported = builder:import_function("host", "pow", { "f64", "f64" }, { "f64" })
  local own = builder:add_function({ "f64" }, { "f64" }, {}, "\x20\x00")
  assert(imported == 0 and own == 1, "an import takes the first index")
  assert(not pcall(builder.import_function, builder, "host", "late", {}, { "f64" }),
    "an import after a function would renumber the calls")
end

function T.compiles_the_subset_and_says_what_it_exports()
  local bytes, info = compile.chunk([[
function add(a, b)
  return a + b
end

local function secret(x)
  return x * 2
end

function doubled(x)
  return secret(x)
end
]], { filename = "part.lua" })

  assert(#bytes > 0 and bytes:sub(1, 4) == "\0asm")
  assert(table.concat(info.exports, ",") == "add,doubled", "a local function stays inside")
  assert(info.arities.add == 2 and info.arities.doubled == 1)
  assert(#info.host == 0, "nothing here needs the host")

  local again = compile.chunk([[
function add(a, b)
  return a + b
end

local function secret(x)
  return x * 2
end

function doubled(x)
  return secret(x)
end
]], { filename = "part.lua" })
  assert(again == bytes, "the same source compiles to the same bytes")
end

function T.asks_the_host_only_for_what_it_cannot_do_itself()
  local _, plain = compile.chunk("function f(a) return math.sqrt(a) end")
  assert(#plain.host == 0, "a square root is an instruction")
  local _, raised = compile.chunk("function f(a, b) return a ^ b end")
  assert(raised.host[1] == "pow", "there is no wasm instruction for a power")
end

function T.refuses_what_the_subset_does_not_cover()
  assert(compile_error("function f(...) return ... end"):find("only read as", 1, true))
  assert(compile_error("function f(a) return a:upper() end"):find("is not an expression", 1, true))
  assert(compile_error("function f(...) local t = ... return t end"):find("only read as", 1, true))
  assert(compile_error("function f() return 1 % 0 ^ coroutine end")
    :find("is not a value this part knows", 1, true))
  assert(compile_error('function f() return math.pi end')
    :find("something to call, not a value", 1, true))
  assert(compile_error("function f() return missing(1) end")
    :find("is not a function this part can call", 1, true))
  assert(compile_error("function f(a) return a end function f(a) return a end")
    :find("declared twice", 1, true))
  assert(compile_error("function f() return g(1) end function g(a, b) return a + b end")
    :find("takes 2, not 1", 1, true))
  assert(compile_error("function f() break end"):find("no loop around it", 1, true))
  assert(compile_error("function f(n) for i = 1, n, 0 do end return 0 end")
    :find("never ends", 1, true))
  assert(compile_error("function f(n) for i = 1, n, n do end return 0 end")
    :find("a step that is a plain number", 1, true))
  assert(compile_error("function f() return unknown end")
    :find("is not a value this part knows", 1, true))
  assert(compile_error("function f() for i = 1, 3 do local g = function() return i end end return 0 end")
    :find("a closure keeps", 1, true))
end

function T.points_at_the_line_that_is_wrong()
  local message = compile_error("function f(a)\n  return a\nend\n\nfunction g()\n  return nope\nend")
  assert(message:find("part%.lua:6:"), message)
end

function T.splits_a_program_into_parts_that_only_need_what_they_call()
  local manifest = parts_lib.build({
    { name = "numbers", source = "function twice(x) return x * 2 end" },
    { name = "shapes", source = "function area(r) return 3.14 * r * r end\n"
      .. "function wide(r) return twice(area(r)) end" },
    { name = "lonely", source = "function solo(x) return x + 1 end" },
  })

  assert(manifest.index.wide == "shapes" and manifest.index.twice == "numbers")
  assert(table.concat(manifest.parts.shapes.needs, ",") == "numbers")
  assert(#manifest.parts.numbers.needs == 0)
  assert(#manifest.parts.lonely.needs == 0, "a part that calls nobody carries nobody")

  assert(table.concat(parts_lib.chain(manifest, "wide"), ",") == "numbers,shapes")
  assert(table.concat(parts_lib.chain(manifest, "solo"), ",") == "lonely",
    "asking for one function does not drag the others in")
  assert(parts_lib.chain(manifest, "absent") == nil)

  local ok, err = pcall(parts_lib.build, {
    { name = "a", source = "function same(x) return x end" },
    { name = "b", source = "function same(x) return x end" },
  })
  assert(not ok and tostring(err):find("exported by both", 1, true))
end

function T.a_part_imports_a_name_only_when_it_calls_it()
  local manifest = parts_lib.build({
    { name = "base", source = "function one() return 1 end\nfunction two() return 2 end" },
    { name = "user", source = "function three() return one() + 2 end" },
  })
  local bytes = manifest.parts.user.bytes
  assert(bytes:find("one", 1, true), "the name it calls is imported")
  assert(not bytes:find("two", 1, true), "the name it never calls is not")
end

function T.carries_strings_in_the_memory_the_host_hands_it()
  local bytes, info = compile.chunk([[
function greeting(loud)
  if loud then
    return "hello" .. "!"
  end
  return "hello"
end

function size()
  return #"hello"
end
]], { filename = "text.lua", data_base = 2048 })

  assert(info.memory, "a part with strings needs the memory")
  assert(table.concat(info.needs, ",") == "runtime", "and the runtime beside it")
  assert(info.data_size == 32, "two literals, each padded to a cell: " .. info.data_size)
  assert(info.data:find("hello", 1, true), "the bytes travel in the module")
  assert(select(2, info.data:gsub("hello", "")) == 1, "the same literal is written once")
  assert(bytes:find("hello", 1, true))
end

function T.builds_the_runtime_part_only_for_the_parts_that_need_it()
  local plain = parts_lib.build({
    { name = "numbers", source = "function twice(x) return x * 2 end" },
  })
  assert(plain.parts.runtime == nil, "numbers alone need no runtime")

  local manifest = parts_lib.build({
    { name = "text", source = 'function hello() return "a" .. "b" end' },
  })
  local runtime = manifest.parts.runtime
  assert(runtime, "a part with strings brings the runtime")
  assert(manifest.order[1] == "runtime", "and it comes first")
  assert(runtime.internal, "it is Lunar's own, not the application's")
  assert(manifest.index.concat == nil, "its exports are not names an app can ask for")
  assert(manifest.index.hello == "text")
  assert(table.concat(manifest.parts.text.needs, ",") == "runtime")
  assert(manifest.heap >= 1024, "the heap starts after the literals: " .. manifest.heap)

  local ok, err = pcall(parts_lib.build, {
    { name = "runtime", source = "function twice(x) return x * 2 end" },
  })
  assert(not ok and tostring(err):find("Lunar's own wasm part", 1, true), tostring(err))
end

function T.gives_each_part_its_own_room_in_the_memory()
  local manifest = parts_lib.build({
    { name = "first", source = 'function a() return "0123456789abcdef" end' },
    { name = "second", source = 'function b() return "x" end' },
  })
  assert(manifest.parts.first.bytes:find("0123456789abcdef", 1, true))
  assert(manifest.parts.second.bytes:find("x", 1, true))
  assert(manifest.heap >= 1024 + 24 + 16, "the second part sits after the first: " .. manifest.heap)
end

function T.compiles_tables_through_the_runtime()
  local _, info = compile.chunk([[
function build()
  local t = { 1, 2, name = "lunar" }
  t[3] = 3
  t.name = "moon"
  return t
end

function read(t)
  return t[1] + #t
end
]], { filename = "tables.lua" })
  assert(table.concat(info.needs, ",") == "runtime")
  assert(info.memory)
end

function T.gives_every_function_a_slot_in_the_shared_table()
  local _, info = compile.chunk([[
function counter(start)
  local total = start
  local function bump(by)
    total = total + by
    return total
  end
  bump(1)
  return total
end

function plain(x)
  return x + 1
end
]], { filename = "closures.lua", table_base = 7 })

  assert(info.table_slots == 3, "two declarations and one closure: " .. info.table_slots)
  assert(info.table_base == 7)
  assert(table.concat(info.needs, ",") == "runtime", "a closure needs the allocator")
  assert(info.memory, "and the memory the cell lives in")

  local manifest = parts_lib.build({
    { name = "a", source = "function one() local f = function() return 1 end return f() end" },
    { name = "b", source = "function two() return 2 end" },
  })
  assert(manifest.table_size >= 4, "the slots of every part fit in one table: " .. manifest.table_size)
  assert(manifest.parts.a.bytes:sub(1, 4) == "\0asm")
end

function T.knows_the_names_lua_gives_a_table_its_manners_with()
  local _, info = compile.chunk([[
function defaulted()
  local t = setmetatable({}, { __index = { colour = "blue" } })
  return t.colour
end

function kind(value)
  return type(value)
end

function raw(t)
  rawset(t, 1, 2)
  return rawget(t, 1)
end
]], { filename = "meta.lua" })
  assert(table.concat(info.needs, ",") == "runtime")
  assert(info.exports[1] == "defaulted")

  assert(compile_error("function f(t) return setmetatable(t) end")
    :find("takes 2, not 1", 1, true))

  local shadowed = compile.chunk([[
function type(x)
  return x
end

function f(v)
  return type(v)
end
]], { filename = "shadow.lua" })
  assert(#shadowed > 0, "a part may still name a function `type` itself")
end

function T.hands_back_more_than_one_value()
  local _, info = compile.chunk([[
function pair(n)
  return n, n * 2
end

function sum(n)
  local a, b = pair(n)
  return a + b
end

function swap(x, y)
  local a, b = x, y
  a, b = b, a
  return a - b
end
]], { filename = "multi.lua" })
  assert(info.memory, "the extra values travel through the memory")
  assert(#info.needs == 0, "and need nothing else")
  assert(table.concat(info.exports, ",") == "pair,sum,swap")

  assert(compile_error("function f() return 1, 2, 3, 4, 5, 6, 7, 8, 9 end")
    :find("at most", 1, true))
end

function T.takes_a_vararg_and_reads_it_as_a_table()
  local _, info = compile.chunk([[
function total(...)
  local values = {...}
  return #values
end

function how_many(...)
  return select("#", ...)
end

function pass()
  return total(1, 2, 3)
end
]], { filename = "va.lua" })
  assert(table.concat(info.needs, ",") == "runtime")
  assert(info.arities.total == 0, "the fixed parameters are what the arity counts")

  assert(compile_error("function f() local t = {...} return #t end")
    :find("outside a function that takes it", 1, true))
  assert(compile_error("function f(a, ...) return 0 end function g() return f() end")
    :find("at least 1, not 0", 1, true))
end

local function fake_browser(manifest)
  local log = {}

  local function promise(value)
    local self = {}
    function self.resolve(_, handler)
      local produced = handler(value)
      if type(produced) == "table" and produced.is_promise then return produced end
      return promise(produced)
    end
    self["then"] = self.resolve
    self["catch"] = function(_) return self end
    self.is_promise = true
    return self
  end

  local window = { Object = {}, Math = { pow = function(a, b) return a ^ b end } }
  window.console = { warn = function(_, message) log[#log + 1] = "warn " .. message end }

  window.WebAssembly = {
    instantiate = function(_, buffer, imports)
      log[#log + 1] = "instantiate " .. buffer.part
      local exports = {}
      for _, name in ipairs(manifest.parts[buffer.part].exports) do
        exports[name] = function() return name .. "!" end
      end
      return promise({ instance = { exports = exports, imports = imports } })
    end,
  }

  function window:fetch(url)
    log[#log + 1] = "fetch " .. url
    if url:find("index.json", 1, true) then
      local json = require("lunar.core.json")
      local wasm_site = require("lunar.site.wasm")
      local text = json.encode(wasm_site.index(manifest))
      return promise({ ok = true, text = function() return promise(text) end })
    end
    local name = url:match("/([%w_%-]+)%.wasm")
    return promise({ ok = true,
      arrayBuffer = function() return promise({ part = name }) end })
  end

  local js = { new = function() return {} end }
  return window, js, log
end

function T.loads_a_part_and_everything_it_needs_once()
  local manifest = parts_lib.build({
    { name = "numbers", source = "function twice(x) return x * 2 end" },
    { name = "shapes", source = "function wide(r) return twice(r) end" },
  })
  manifest.digest = "test"

  local window, js, log = fake_browser(manifest)
  local loader = wasm_runtime.browser(window, js)

  local got
  loader:load("wide", function(fn) got = fn() end)
  assert(got == "wide!", "the export came back")
  assert(table.concat(log, " | "):find("fetch /_lunar/wasm/index.json", 1, true))
  assert(table.concat(log, " | "):find("instantiate numbers | fetch /_lunar/wasm/shapes", 1, true),
    "what it needs is instantiated first: " .. table.concat(log, " | "))

  local before = #log
  loader:load("twice", function(fn) got = fn() end)
  assert(got == "twice!")
  assert(#log == before, "the second call touched the network not at all")
  assert(loader:loaded("numbers") and loader:loaded("shapes"))
end

function T.says_what_went_wrong_rather_than_failing_quietly()
  local manifest = parts_lib.build({
    { name = "numbers", source = "function twice(x) return x * 2 end" },
  })
  manifest.digest = "test"
  local window, js = fake_browser(manifest)
  local loader = wasm_runtime.browser(window, js)

  local message
  loader:load("absent", function() end, function(reason) message = reason end)
  assert(message and message:find("no wasm part exports", 1, true), tostring(message))
end

return T
