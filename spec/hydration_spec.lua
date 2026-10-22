local support = require("support")
local mock = require("mockdom")

local T = {}

function T.claims_every_fixture_rather_than_rebuilding_it()
  support.assert_claims(support.component("Counter"), { start = 0 })
  support.assert_claims(support.component("Counter"), { start = 5, label = "taps" })
  support.assert_claims(support.component("Counter"), { start = -2 })
  support.assert_claims(support.component("Card"), { title = "Hello", tone = "warn" })
  support.assert_claims(support.component("List"), { items = {} })
  support.assert_claims(support.component("List"), {
    items = { { name = "one", done = true }, { name = "two" } },
  })
  support.assert_claims(support.component("App"), {})
  support.assert_claims(support.component("App"), { heading = "Demo" })
end

function T.writes_nothing_the_server_already_wrote()
  local run = support.assert_claims(support.component("Counter"), { start = 1 })
  assert(run.counts.created == 0, "no element was built")
  assert(run.counts.appended == 0, "nothing was appended: it was already there")
  assert(run.counts.attributes == 0, "no attribute was rewritten")
  assert(run.counts.text == 0, "no text node was rewritten")
end

function T.the_nodes_survive_with_what_was_on_them()
  local markup = support.ssr(support.component("App"), {})
  local dom = mock.parse(markup)
  local input
  for _, candidate in ipairs(support.nodes_of_tag(dom.body, "input")) do
    if candidate.attributes.class == "name" then input = candidate end
  end
  assert(input, "the server sent the input")
  input.properties.focused = true
  input.properties.value = "typed"

  local instance = support.component("App")
  local mounted = require("lunar.runtime.component").mount(instance, dom.body, {}, {
    dom = dom, hydrate = true,
    on_rebuild = function(why) error("gave up: " .. tostring(why)) end,
  })

  local still
  for _, candidate in ipairs(support.nodes_of_tag(dom.body, "input")) do
    if candidate.attributes.class == "name" then still = candidate end
  end
  assert(still == input, "the input is the same node")
  assert(still.properties.focused == true, "and nothing touched what was on it")

  support.input(still, "moon")
  assert(support.serialize(dom.body):find("Hi moon", 1, true))
  assert(mounted)
end

function T.splits_a_text_node_the_document_merged()
  local def = support.source([[
<script>
  props { name = "world" }
</script>
<p>Hello {name}, and goodbye.</p>
]], "Split.lunar")

  local run = support.assert_claims(def, { name = "moon" })
  local paragraph = support.find(run.dom, "p")
  assert(#paragraph.children == 3,
    "three nodes: the text before, the expression, the text after")

  run.instance.scope.name = "mars"
  assert(support.serialize(run.dom.body):find("Hello mars, and goodbye.", 1, true))
end

function T.puts_a_node_back_where_the_server_rendered_nothing()
  local def = support.source([[
<script>
  props { name = "" }
</script>
<p>Hi {name}!</p>
]], "Empty.lunar")

  local run = support.assert_claims(def, { name = "" })
  run.instance.scope.name = "there"
  assert(support.serialize(run.dom.body):find("<p>Hi there!</p>", 1, true))
end

function T.claims_blocks_and_keeps_them_working()
  local def = support.source([[
<script>
  props { items = {}, show = true }
</script>
<ul>{#each items as item, index}<li>{index}: {item}</li>{:else}<li>none</li>{/each}</ul>
<div>{#if show}<span>on</span>{/if}</div>
]], "Blocks.lunar")

  local empty = support.assert_claims(def, { items = {}, show = false })
  empty.instance.scope.items = { "a", "b" }
  assert(support.serialize(empty.dom.body):find("<li>1: a</li><li>2: b</li>", 1, true))
  empty.instance.scope.show = true
  assert(support.serialize(empty.dom.body):find("<div><span>on</span></div>", 1, true))

  local full = support.assert_claims(def, { items = { "x", "y", "z" }, show = true })
  full.instance.scope.items = { "one" }
  assert(support.serialize(full.dom.body):find("<ul><li>1: one</li></ul>", 1, true))
  full.instance.scope.show = false
  assert(support.serialize(full.dom.body):find("<div></div>", 1, true))
end

function T.claims_a_block_nested_in_a_block()
  local def = support.source([[
<script>
  props { outer = true, inner = false }
</script>
<div>{#if outer}<b>yes</b>{#if inner}<i>deep</i>{/if}{/if}</div>
]], "Nested.lunar")

  local run = support.assert_claims(def, { outer = true, inner = false })
  run.instance.scope.inner = true
  assert(support.serialize(run.dom.body):find("<b>yes</b><i>deep</i>", 1, true))
  run.instance.scope.outer = false
  assert(support.serialize(run.dom.body):find("<div></div>", 1, true))
  run.instance.scope.outer = true
  assert(support.serialize(run.dom.body):find("<b>yes</b><i>deep</i>", 1, true))
end

function T.claims_the_markup_of_an_html_block()
  local def = support.component("Escapes")
  support.assert_claims(def, { value = "plain", markup = "<b>bold</b><i>italic</i>" })

  local run = support.assert_claims(def, { value = "x", markup = "<em>one</em>" })
  run.instance.scope.markup = "<strong>two</strong>"
  assert(support.serialize(run.dom.body):find("<strong>two</strong>", 1, true))
end

function T.gives_up_and_rebuilds_when_the_markup_is_not_what_it_built()
  local def = support.component("Counter")
  local run = support.hydrate(def, { start = 0 },
    { markup = "<section><p>a page from somewhere else</p></section>" })

  assert(run.claimed == false, "it did not claim")
  assert(run.reason and run.reason ~= "", "and said why")
  local markup = support.serialize(run.dom.body)
  assert(markup == support.ssr(def, { start = 0 }), "and the page is correct anyway")
  assert(not markup:find("somewhere else", 1, true), "nothing of the old one is left")

  local _, buttons = support.find(run.dom, "button")
  support.fire(buttons[2], "click")
  assert(support.serialize(run.dom.body):find(">1 clicks<", 1, true))
end

function T.rebuilds_when_the_two_renderers_disagree_about_a_text()
  local def = support.source([[
<script>
  props { name = "world" }
</script>
<p>Hello {name}.</p>
]], "Drift.lunar")

  local run = support.hydrate(def, { name = "moon" },
    { markup = support.ssr(def, { name = "mars" }) })
  assert(run.claimed == false, "it did not claim")
  assert(run.reason:find("mars", 1, true), run.reason)
  assert(support.serialize(run.dom.body) == support.ssr(def, { name = "moon" }),
    "and the page is the browser's, which is the one that can keep up")
end

function T.runs_the_rise_hooks_once_the_page_is_claimed()
  local def = support.source([[
<script>
  props { label = "ready" }
  seen = "no"
  on_rise(function() seen = "yes" end)
</script>
<p>{label} {seen}</p>
]], "Rise.lunar")

  local run = support.hydrate(def, { label = "hello" })
  assert(run.claimed, run.reason)
  assert(support.serialize(run.dom.body):find("hello yes", 1, true),
    "the hook ran and the text followed it")
end

return T
