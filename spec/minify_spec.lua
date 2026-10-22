local bundle = require("lunar.site.bundle")
local fs = require("lunar.core.fs")
local lunar = require("lunar")
local minify = require("lunar.core.minify")
local util = require("lunar.core.util")

local T = {}

local FRAMEWORK = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/spec/[^/]*$") or ".")

local function same(source, wanted, message)
  local got = minify.lua_source(source)
  assert(got == wanted, string.format("%s\n  wanted %q\n  got    %q",
    message or "the minifier disagreed", wanted, got))
end

function T.drops_what_only_a_reader_needs()
  same("local a = 1 -- a trailing comment\nreturn a\n", "local a = 1\nreturn a\n")
  same("--[[ a long\ncomment ]]local a = 1\n", "local a = 1\n")
  same("  local   x   =   1  \n\n\n  return x\n", "local x = 1\nreturn x\n")
  same("local t = {\n  a = 1,\n  b = 2,\n}\n", "local t = {\na = 1,\nb = 2,\n}\n")
end

function T.leaves_strings_exactly_as_they_are()
  same('local s = "-- not a comment"\n', 'local s = "-- not a comment"\n')
  same("local s = '  spaces  '\n", "local s = '  spaces  '\n")
  same("local s = [[keep\n  these\nlines]]\n", "local s = [[keep\n  these\nlines]]\n")
  same("local s = [==[a ]] b]==]\n", "local s = [==[a ]] b]==]\n")
  same('local s = "a \\" -- b"\n', 'local s = "a \\" -- b"\n')
end

function T.does_not_glue_tokens_together()
  same("local a = b - -c\n", "local a = b - -c\n")
  same("local a = b\nlocal c = d\n", "local a = b\nlocal c = d\n")
  same("return a\n", "return a\n")
  for _, source in ipairs({
    "local a = 1 local b = 2 return a + b",
    "if a then return b end",
    "for index = 1, 10 do print(index) end",
    "local s = 1 --[==[x]==] + 2",
  }) do
    assert(load(minify.lua_source(source)), "the minified chunk does not load: " .. source)
  end
end

function T.every_framework_module_still_loads_and_is_no_larger()
  local seen = {}
  local modules = {}
  for _, list in ipairs({ bundle.MODULES, bundle.SERVER_MODULES }) do
    for _, relative in ipairs(list) do
      if not seen[relative] then
        seen[relative] = true
        modules[#modules + 1] = relative
      end
    end
  end
  assert(#modules > 10, "there are modules to check")

  local raw, small = 0, 0
  for _, relative in ipairs(modules) do
    local path = fs.join(FRAMEWORK, relative)
    local source = assert(util.read_file(path), relative .. " is missing")
    local minified = minify.lua_source(source)
    assert(load(minified, "@" .. relative), relative .. " does not load once minified")
    assert(#minified <= #source, relative .. " grew")
    assert(minify.lua_source(minified) == minified, relative .. " is not stable")
    raw = raw + #source
    small = small + #minified
  end
  assert(small < raw, "nothing was saved at all")
end

function T.a_minified_module_behaves_the_same()
  local path = fs.join(FRAMEWORK, "lunar/core/html.lua")
  local source = assert(util.read_file(path))
  local plain = assert(load(source, "@html"))()
  local small = assert(load(minify.lua_source(source), "@html"))()

  for _, value in ipairs({ "a & b", "<script>", 'quote "', "plain" }) do
    assert(plain.escape(value) == small.escape(value), value)
  end
  assert(plain.attr("class", "a b") == small.attr("class", "a b"))
  assert(plain.class_list("a", { { "b", true }, { "c", false } }, "d")
    == small.class_list("a", { { "b", true }, { "c", false } }, "d"))
end

function T.the_flag_decides_and_production_is_the_default()
  local root = "examples/tranquility"
  local development = lunar.app({ root = root, dev = true, version = "spec" })
  assert(development.minify == false, "dev leaves the source alone")

  local production = lunar.app({ root = root, dev = false, version = "spec" })
  assert(production.minify == true, "production minifies")

  local off = lunar.app({ root = root, dev = false, version = "spec", minify = false })
  assert(off.minify == false, "and the flag turns it off")

  local small = assert(bundle.build(production))
  local whole = assert(bundle.build(off))
  assert(#small < #whole, "the minified bundle is smaller")
  assert(load(small, "@moonlight"), "and it still loads")
end

return T
