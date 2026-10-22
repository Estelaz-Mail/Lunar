local compile = require("lunar.wasm.compile")
local encode = require("lunar.wasm.encode")
local module_lib = require("lunar.wasm.module")
local parts_lib = require("lunar.wasm.parts")

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
  local imported = builder:import_function("lunar", "pow", { "f64", "f64" }, { "f64" })
  local own = builder:add_function({ "f64" }, { "f64" }, {}, "\x20\x00")
  assert(imported == 0 and own == 1, "an import takes the first index")
  assert(not pcall(builder.import_function, builder, "lunar", "late", {}, { "f64" }),
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
  assert(compile_error('function f() return "text" end'):find("has no place here", 1, true))
  assert(compile_error("function f() return {} end"):find("is not an expression", 1, true))
  assert(compile_error("function f(a) local t = a .. a return t end")
    :find("not part of the wasm subset", 1, true))
  assert(compile_error("function f(a) return a < 1 end")
    :find("truth value", 1, true))
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
  assert(compile_error("function f() local function g() end return 0 end")
    :find("nested `local function`", 1, true))
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

return T
