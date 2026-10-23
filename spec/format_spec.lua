local formatter = require("lunar.format")
local parser = require("lunar.compiler.parser")
local support = require("support")

local suite = {}

local function rendered(source)
  return (support.ssr(support.source(source)):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function formatted(source, options)
  local result = formatter.source(source, options)
  assert(result == formatter.source(result, options), "formatting must be idempotent")
  return result
end

function suite.nested_markup_and_blocks()
  local source = '<script>items={1,2}</script><main><section>{#if true}<ul>{#each items as item, i}<li>{i}: {item}</li>{:else}<li>Empty</li>{/each}</ul>{:else if false}<p>No</p>{:else}<p>Other</p>{/if}</section></main>'
  local result = formatted(source)
  assert(result:find("<main>\n  <section>\n    {#if true}\n      <ul>", 1, true), result)
  assert(result:find("        {:else}\n          <li>Empty</li>", 1, true), result)
  assert(result:find("    {:else if false}\n      <p>No</p>", 1, true), result)
end

function suite.inline_text_spacing_and_escaped_braces()
  for _, source in ipairs({
    '<p>Hello <strong>world</strong>!</p>',
    '<div><span>a</span><span>b</span></div>',
    '<div><span>a</span> <span>b</span></div>',
    '<p> A &amp; B \\{literal\\} {2 + 2} </p>',
    '<p>line one\nline two <em>three</em></p>',
    'Hello <strong>world</strong>!  ',
    '  plain text\n',
  }) do
    local result = formatted(source)
    assert(rendered(source) == rendered(result), result)
  end
end

function suite.root_expressions_and_head_metadata()
  local source = '<script>title="Hello"</script><lunar:head><title>{title}</title></lunar:head>{title}'
  local result = formatted(source)
  assert(result:find('<title>{title}</title>', 1, true), result)
  assert(rendered(source) == rendered(result))
end

function suite.protected_elements_are_byte_preserved()
  local source = '<main><pre>  alpha\n    <code>a  b\n c</code>\n</pre><code>  x  </code><textarea> a\n  b </textarea></main>'
  local result = formatted(source)
  for _, literal in ipairs({ '<pre>  alpha\n    <code>a  b\n c</code>\n</pre>', '<code>  x  </code>', '<textarea> a\n  b </textarea>' }) do
    assert(result:find(literal, 1, true), result)
  end
end

function suite.lua_literals_comments_and_spacing()
  local source = [=[<script>
value=[==[line one
  line two]==]
-- words stay here
local function adjust(x)
if x>0 then
return x%2
else
return - -x
end
end
number=adjust(5)
</script><p>{value} {number}</p>]=]
  local result = formatted(source)
  assert(result:find("  local function adjust(x)\n    if x > 0 then\n      return x % 2", 1, true), result)
  assert(result:find("[==[line one\n  line two]==]", 1, true))
  assert(rendered(source) == rendered(result))
end

function suite.css_strings_functions_custom_properties_and_nested_rules()
  local source = [=[<style>@media(min-width:1px){p{content:"a;{b}";background:url("data:image/svg+xml;a{b}");--shape:{a:b;c:d};color:red;}}p:hover{color:blue}</style><p>Hi</p>]=]
  local result = formatted(source)
  assert(result:find('    p {\n      content: "a;{b}";', 1, true), result)
  assert(result:find('--shape: {a:b;c:d};', 1, true), result)
  assert(result:find('url("data:image/svg+xml;a{b}")', 1, true), result)
end

function suite.css_escaped_delimiters_and_spaces()
  local result = formatted('<style>.escaped\\{name{--space:\\ ;content:"x\\\";{}";color:red}</style><p>Hi</p>')
  assert(result:find('.escaped\\{name {', 1, true), result)
  assert(result:find('--space: \\ ;', 1, true), result)
end

function suite.width_attributes_and_indentation()
  local result = formatted('<section id = "test" aria-label="A rather long label" class="sample"><div><br/><slot/></div></section>', { width = 40, indent = 4 })
  assert(result:find('<section\n    id="test"\n    aria-label="A rather long label"\n    class="sample"\n>', 1, true), result)
  assert(result:find('    <div><br /><slot /></div>', 1, true), result)
end

function suite.attributes_and_expressions_remain_literal()
  local source = '<script>value="ok"</script><button title="A {value} B" on:click={function() value = "x}y" end} {...{id="foo"}}>Count {value}</button>'
  local result = formatted(source)
  assert(result:find('on:click={function() value = "x}y" end}', 1, true), result)
  assert(rendered(source) == rendered(result))
end

function suite.tokens_round_trip_and_closing_tag_whitespace()
  local source = '<!-- a --><section><p>{"a}b"}</ p></ section>'
  local parts = {}
  for _, token in ipairs(parser.tokens(source)) do parts[#parts + 1] = token.raw end
  assert(table.concat(parts) == source)
  assert(formatted(source):find('<p>{"a}b"}</p>', 1, true))
end

function suite.invalid_source_and_options_are_rejected()
  for _, source in ipairs({ '<div>', '<script>local =</script><p>x</p>', '{#if true}<p>x</p>', '<p>{missing +}</p>' }) do
    assert(not pcall(formatter.source, source), source)
  end
  for _, options in ipairs({ { indent = 0 }, { indent = 1.5 }, { width = 20 }, { width = "100" } }) do
    assert(not pcall(formatter.source, '<p>x</p>', options))
  end
end

function suite.does_not_execute_component_scripts()
  local result = formatted('<script>error("must not run")</script><p>Safe</p>')
  assert(result:find('error("must not run")', 1, true))
end

return suite
