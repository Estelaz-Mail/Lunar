local compiler = require("lunar.compiler")
local component = require("lunar.runtime.component")
local parser = require("lunar.compiler.parser")
local sfc = require("lunar.compiler.sfc")
local support = require("support")

local T = {}

local function compile_error(source)
  local ok, err = pcall(compiler.compile, source, { path = "T.lunar" })
  assert(not ok, "expected this to be refused: " .. source)
  return tostring(err)
end

function T.splits_the_three_parts_and_keeps_the_line_numbers()
  local parts = sfc.split("<script>\nlocal x = 1\n</script>\n<p>hi</p>\n<style>\np{}\n</style>\n",
    "T.lunar")
  assert(parts.script == "\nlocal x = 1\n")
  assert(parts.script_line == 1)
  assert(parts.style == "\np{}\n")
  local line = 1
  for _ in parts.template:sub(1, parts.template:find("<p>")):gmatch("\n") do line = line + 1 end
  assert(line == 4, "got line " .. line)
end

function T.a_component_without_a_script_or_a_style_still_compiles()
  local def = support.source("<p>plain</p>", "Plain.lunar")
  assert(component.render(def, {}) == "<p>plain</p>")
  assert(def.css == nil)
  assert(def.scope_class == nil)
end

function T.refuses_a_second_script()
  assert(compile_error("<script>a=1</script><p/><script>b=2</script>")
    :find("one <script>", 1, true))
end

function T.points_at_the_line_a_template_error_is_on()
  local message = compile_error("<p>ok</p>\n\n{#if x}\n<p>y</p>\n")
  assert(message:find("T.lunar:3", 1, true), message)
  assert(message:find("never closed", 1, true))
end

function T.names_the_element_that_was_left_open()
  local message = compile_error("<div>\n<p>\n</div>")
  assert(message:find("</div> closes <p>", 1, true), message)
  assert(message:find("line 2", 1, true))
end

function T.refuses_an_expression_that_is_not_lua()
  local message = compile_error("<p>{a +}</p>")
  assert(message:find("is not a Lua expression", 1, true), message)
  assert(message:find("T.lunar:1", 1, true))
end

function T.refuses_a_block_that_does_not_exist()
  assert(compile_error("{#unless x}a{/unless}"):find("unknown block", 1, true))
  assert(compile_error("{#await p}a{/await}"):find("not part of Lunar", 1, true))
  assert(compile_error("{@wat x}"):find("unknown directive", 1, true))
end

function T.refuses_a_closing_tag_for_a_block_that_is_not_open()
  assert(compile_error("{/if}"):find("with no block open", 1, true))
  assert(compile_error("{#if a}x{/each}"):find("closes a {#if}", 1, true))
  assert(compile_error("{:else}"):find("outside a block", 1, true))
end

function T.refuses_an_each_it_cannot_read()
  assert(compile_error("{#each items}x{/each}"):find("list as item", 1, true))
  assert(compile_error("{#each items as a b}x{/each}"):find("is not a name", 1, true))
  assert(compile_error("{#each items as item (item.id)}x{/each}")
    :find("keyed", 1, true))
end

function T.refuses_a_directive_that_is_a_typo()
  assert(compile_error("<p onn:click={f}>x</p>"):find("unknown directive", 1, true))
  assert(compile_error("<p on:click>x</p>"):find("wants a handler", 1, true))
  assert(compile_error("<p on:click|nope={f}>x</p>"):find("unknown event modifier", 1, true))
  assert(compile_error("<p class:a>x</p>"):find("wants an expression", 1, true))
end

function T.refuses_a_binding_to_something_that_cannot_be_assigned()
  assert(compile_error("<input bind:value={a + 1} />")
    :find("cannot be assigned to", 1, true))
end

function T.refuses_a_closing_tag_for_a_void_element()
  assert(compile_error("<br>text</br>"):find("with no element open", 1, true))
end

function T.refuses_what_a_component_cannot_do()
  assert(compile_error("<Card on:click={f} />"):find("pass the handler as one", 1, true))
  assert(compile_error("<Card bind:x={y} />"):find("not part of Lunar", 1, true))
end

function T.a_runtime_error_in_a_script_points_at_the_component_line()
  local source = "<script>\n\n\nerror(\"boom\")\n</script>\n<p>x</p>"
  local def = compiler.load(source, { path = "Boom.lunar", filename = "Boom.lunar" })
  local ok, err = pcall(component.render, def, {})
  assert(not ok)
  assert(tostring(err):find("Boom.lunar:4", 1, true), tostring(err))
end

function T.parses_the_braces_a_lua_expression_can_contain()
  local def = support.source(
    '<p>{ (function() local t = { a = "}" } return t.a end)() }</p>', "Braces.lunar")
  assert(component.render(def, {}) == "<p>}</p>")
end

function T.keeps_the_text_of_a_raw_element_verbatim()
  local nodes = parser.parse('<script type="application/json">{"a": 1}</script>',
    { filename = "T.lunar" })
  assert(nodes[1].raw_text == true)
  assert(nodes[1].children[1].value == '{"a": 1}')
end

function T.decodes_the_entities_a_template_contains()
  local def = support.source("<p title=\"a &amp; b\">5 &lt; 6 &nbsp;&#65;</p>", "E.lunar")
  local markup = support.assert_same(def, {})
  assert(markup:find("5 &lt; 6", 1, true), markup)
  assert(markup:find('title="a &amp; b"', 1, true), markup)
  assert(markup:find("A", 1, true))
end

return T
