local support = require("support")

local T = {}

function T.renders_a_counter_the_same_way_in_both_renderers()
  local def = support.component("Counter")
  support.assert_same(def, {})
  support.assert_same(def, { start = 5, label = "taps" })
  support.assert_same(def, { start = -2 })
end

function T.a_click_updates_the_text_the_class_and_the_branch()
  local def = support.component("Counter")
  local _, dom = support.client(def, { start = 0 })
  local output = support.find(dom, "output")
  local _, buttons = support.find(dom, "button")

  assert(support.outer(output):find(">0 clicks<", 1, true))
  assert(support.outer(output):find("zero", 1, true), "class:zero is on at zero")

  support.fire(buttons[2], "click")
  support.fire(buttons[2], "click")
  support.fire(buttons[2], "click")
  local markup = support.serialize(dom.body)
  assert(markup:find(">3 clicks<", 1, true))
  assert(markup:find("6 halves", 1, true), "the derived value followed")
  assert(not markup:find("zero", 1, true))
  assert(markup:find('data-count="3"', 1, true), "the attribute followed")

  for _ = 1, 5 do support.fire(buttons[1], "click") end
  local below = support.serialize(dom.body)
  assert(below:find("below zero", 1, true), "the {:else if} branch took over")
  assert(below:find("negative", 1, true))
end

function T.the_takeover_produces_what_the_server_sent()
  local def = support.component("Counter")
  local server = support.ssr(def, { start = 3 })
  local browser = support.client(def, { start = 3 })
  assert(server == browser)
  assert(server:find("6 halves", 1, true))
end

function T.renders_a_list_and_its_empty_case()
  local def = support.component("List")
  support.assert_same(def, { items = {} })
  support.assert_same(def, {
    items = { { name = "one", done = true }, { name = "two" } },
  })

  local markup = support.ssr(def, { items = {} })
  assert(markup:find("nothing here", 1, true))
  assert(markup:find('class="empty"', 1, true))
end

function T.a_new_list_rebuilds_the_block_and_an_empty_one_takes_the_else()
  local def = support.source([[
<script>
  items = { "a", "b" }
</script>
<ul>{#each items as item, i}<li>{i}{item}</li>{:else}<li>none</li>{/each}</ul>
]], "Each.lunar")

  local markup, dom, instance = support.client(def, {})
  assert(markup:find("<li>1a</li><li>2b</li>", 1, true), markup)

  instance.scope.items = { "x", "y", "z" }
  assert(support.serialize(dom.body):find("<li>1x</li><li>2y</li><li>3z</li>", 1, true))

  instance.scope.items = {}
  assert(support.serialize(dom.body):find("<li>none</li>", 1, true))

  instance.scope.items = { "back" }
  assert(support.serialize(dom.body):find("<li>1back</li>", 1, true))
end

function T.a_keyed_list_keeps_the_nodes_whose_key_survived()
  local def = support.source([[
<script>
  items = { { id = "a" }, { id = "b" }, { id = "c" } }
</script>
<ul>{#each items as item (item.id)}<li>{item.id}</li>{/each}</ul>
]], "Keyed.lunar")

  local markup, dom, instance = support.client(def, {})
  assert(markup:find("<li>a</li><li>b</li><li>c</li>", 1, true), markup)
  local before = {}
  for _, node in ipairs(select(2, support.find(dom, "li"))) do before[#before + 1] = node end

  local a, b, c = table.unpack(instance.scope.items)
  instance.scope.items = { c, a, b }
  local reordered = support.serialize(dom.body)
  assert(reordered:find("<li>c</li><li>a</li><li>b</li>", 1, true), reordered)

  local after = select(2, support.find(dom, "li"))
  assert(after[1] == before[3] and after[2] == before[1] and after[3] == before[2],
    "the rows moved rather than being rebuilt")

  instance.scope.items = { c, b }
  local removed = select(2, support.find(dom, "li"))
  assert(#removed == 2 and removed[1] == before[3] and removed[2] == before[2],
    "dropping a key left the others alone")

  local d = { id = "d" }
  instance.scope.items = { d, c, b }
  local grown = select(2, support.find(dom, "li"))
  assert(support.serialize(dom.body):find("<li>d</li><li>c</li><li>b</li>", 1, true))
  assert(grown[2] == before[3] and grown[3] == before[2], "a new key did not disturb the rest")
end

function T.a_keyed_list_rebuilds_a_row_whose_item_changed()
  local def = support.source([[
<script>
  items = { { id = "a", label = "one" }, { id = "b", label = "two" } }
</script>
<ul>{#each items as item (item.id)}<li>{item.label}</li>{/each}</ul>
]], "KeyedSwap.lunar")

  local _, dom, instance = support.client(def, {})
  local before = select(2, support.find(dom, "li"))
  local kept = instance.scope.items[2]

  instance.scope.items = { { id = "a", label = "uno" }, kept }
  local after = select(2, support.find(dom, "li"))
  assert(support.serialize(dom.body):find("<li>uno</li><li>two</li>", 1, true))
  assert(after[1] ~= before[1], "the row with a new item was rebuilt")
  assert(after[2] == before[2], "the untouched row was kept")
end

function T.a_keyed_list_takes_the_else_and_comes_back()
  local def = support.source([[
<script>
  items = { { id = "a" } }
</script>
<ul>{#each items as item, i (item.id)}<li>{i}{item.id}</li>{:else}<li>none</li>{/each}</ul>
]], "KeyedElse.lunar")

  local _, dom, instance = support.client(def, {})
  instance.scope.items = {}
  assert(support.serialize(dom.body):find("<li>none</li>", 1, true))
  instance.scope.items = { { id = "b" }, { id = "a" } }
  assert(support.serialize(dom.body):find("<li>1b</li><li>2a</li>", 1, true))
end

function T.a_keyed_list_refuses_the_same_key_twice()
  local def = support.source([[
<script>
  items = { { id = "a" }, { id = "a" } }
</script>
{#each items as item (item.id)}<li>{item.id}</li>{/each}
]], "KeyedTwice.lunar")

  local reported = {}
  local stderr = io.stderr
  io.stderr = { write = function(_, ...) reported[#reported + 1] = table.concat({ ... }) end }
  pcall(support.client, def, {})
  io.stderr = stderr
  assert(table.concat(reported):find("the key a twice", 1, true), table.concat(reported))
end

function T.a_keyed_list_disposes_of_the_rows_it_dropped()
  local def = support.source([[
<script>
  items = { { id = "a" }, { id = "b" }, { id = "c" } }
  tick = 0
</script>
{#each items as item (item.id)}<span>{item.id}-{tick}</span>{/each}
]], "KeyedLeak.lunar")

  local _, _, instance = support.client(def, {})
  local cell = instance.signals.tick
  local function subscribers()
    local total = 0
    for _ in pairs(cell.subscribers) do total = total + 1 end
    return total
  end
  assert(subscribers() == 3, "one effect per row, got " .. subscribers())

  local kept = instance.scope.items[2]
  instance.scope.items = { kept }
  assert(subscribers() == 1, "the dropped rows were disposed, got " .. subscribers())

  instance:destroy()
  assert(subscribers() == 0, "destroying the component disposed the rest")
end

function T.a_keyed_list_renders_the_same_as_an_unkeyed_one()
  local items = { { id = "a" }, { id = "b" } }
  local keyed = support.source([[
<script>
  props { items = {} }
</script>
<ul>{#each items as item, i (item.id)}<li>{i}{item.id}</li>{/each}</ul>
]], "KeyedSame.lunar")
  local plain = support.source([[
<script>
  props { items = {} }
</script>
<ul>{#each items as item, i}<li>{i}{item.id}</li>{/each}</ul>
]], "PlainSame.lunar")

  local markup = support.assert_same(keyed, { items = items })
  assert(markup == support.ssr(plain, { items = items }),
    "a key changes nothing about what is rendered")
end

function T.a_keyed_list_claims_what_the_server_sent()
  local def = support.source([[
<script>
  props { items = {} }
</script>
<ul>{#each items as item (item.id)}<li>{item.id}</li>{/each}</ul>
]], "KeyedHydrate.lunar")
  support.assert_claims(def, { items = { { id = "a" }, { id = "b" } } })
end

function T.renders_a_card_with_a_slot_and_its_fallback()
  local def = support.component("Card")
  support.assert_same(def, {})
  local markup = support.ssr(def, {})
  assert(markup:find("no content", 1, true), "the slot fallback rendered")
end

function T.fills_the_named_slots_and_falls_back_to_the_rest()
  local def = support.component("Panel")
  support.assert_same(def, {})
  local markup = support.ssr(def, {})
  assert(markup:find('<header class="head"><h2>Title</h2></header>', 1, true), markup)
  assert(markup:find('<div class="body"><p>body</p></div>', 1, true), markup)
  assert(markup:find('<footer class="foot">nothing yet</footer>', 1, true),
    "the empty named slot took its fallback")
  assert(not markup:find("slot=", 1, true), "the slot attribute stayed out of the output")
end

function T.a_named_slot_reaches_the_browser_the_same_way()
  local def = support.component("Panel")
  support.assert_claims(def, {})
end

function T.a_component_with_only_named_children_leaves_no_stray_space()
  local def = support.source([[
<script>
  local Shelf = import("./Shelf.lunar")
</script>
<Shelf>
  <h2 slot="head">Title</h2>
</Shelf>
]], support.FIXTURES .. "/Only.lunar")

  local markup = support.assert_same(def, {})
  assert(markup:find('<div class="body"></div>', 1, true), markup)
end

function T.refuses_a_slot_attribute_outside_a_component()
  local ok, err = pcall(support.source, '<div slot="head">x</div>', "Stray.lunar")
  assert(not ok and tostring(err):find("directly inside a component", 1, true), tostring(err))
end

function T.renders_the_whole_feature_set_identically()
  local def = support.component("App")
  support.assert_same(def, {})
  support.assert_same(def, { heading = "Demo" })
end

function T.collects_the_head_and_the_css_of_every_component_it_rendered()
  local def = support.component("App")
  local _, ctx = support.ssr(def, { heading = "Title" })
  assert(#ctx.head == 1)
  assert(ctx.head[1]:find("<title>Title</title>", 1, true))

  local sheets = {}
  for _, sheet in pairs(ctx.css) do sheets[#sheets + 1] = sheet end
  assert(#sheets == 2, "the Card and the Counter have styles, the App does not")
  local all = table.concat(sheets, "\n")
  assert(all:find("%.card%.l%-%x+"))
  assert(all:find("body{ margin: 0 }") or all:find("body { margin: 0 }"),
    ":global was left alone")
end

function T.a_binding_reaches_the_component_that_owns_the_state()
  local def = support.component("App")
  local _, dom = support.client(def, {})
  local _, inputs = support.find(dom, "input")
  local checkbox, text = inputs[1], inputs[2]

  support.input(text, "Lua")
  local markup = support.serialize(dom.body)
  assert(markup:find("Hello Lua", 1, true), "the child's prop followed the parent's state")
  assert(markup:find("Hi Lua,", 1, true))

  support.input(checkbox, true, "checked")
  assert(support.serialize(dom.body):find("agreed: yes", 1, true))
end

function T.escapes_everything_except_what_the_template_said_not_to()
  local def = support.component("Escapes")
  local evil = '<img src=x onerror="alert(1)">'
  local markup = support.assert_same(def, { value = evil, markup = evil })

  assert(markup:find("&lt;img src=x onerror=&quot;alert(1)&quot;&gt;</p>", 1, true), markup)
  assert(markup:find('title="&lt;img', 1, true))
  assert(markup:find("<div><img src=x", 1, true))
end

function T.a_literal_brace_survives()
  local markup = support.assert_same(support.component("App"), {})
  assert(markup:find("{literal}", 1, true))
end

function T.an_event_modifier_does_what_it_says()
  local def = support.source([[
<script>
  outer = 0
  inner = 0
  once_count = 0
</script>
<div on:click={function() outer = outer + 1 end}>
  <button class="stop" on:click|stop={function() inner = inner + 1 end}>stop</button>
  <button class="bubble" on:click={function() inner = inner + 1 end}>bubble</button>
  <button class="once" on:click|once={function() once_count = once_count + 1 end}>once</button>
</div>
<p>{outer}/{inner}/{once_count}</p>
]], "Modifiers.lunar")

  local _, dom, instance = support.client(def, {})
  local _, buttons = support.find(dom, "button")

  support.fire(buttons[2], "click")
  assert(instance.scope.outer == 1, "a click bubbles by default")
  assert(instance.scope.inner == 1)

  support.fire(buttons[1], "click")
  assert(instance.scope.outer == 1, "|stop kept it from bubbling")
  assert(instance.scope.inner == 2)

  support.fire(buttons[3], "click")
  support.fire(buttons[3], "click")
  assert(instance.scope.once_count == 1, "|once fired once")

  local prevented = support.fire(buttons[1], "click")
  assert(prevented.defaultPrevented == false, "|stop is not |prevent")
end

function T.prevent_marks_the_event()
  local def = support.source([[
<form on:submit|prevent={function() submitted = true end}><button>go</button></form>
]], "Prevent.lunar")
  local _, dom, instance = support.client(def, {})
  local form = support.find(dom, "form")
  local event = support.fire(form, "submit")
  assert(event.defaultPrevented == true)
  assert(instance.scope.submitted == true)
end

function T.a_block_disposes_of_what_it_created()
  local signal = require("lunar.runtime.signal")
  local def = support.source([[
<script>
  items = { 1, 2, 3 }
  tick = 0
</script>
{#each items as item}<span>{item}-{tick}</span>{/each}
]], "Leak.lunar")

  local _, dom, instance = support.client(def, {})
  local cell = instance.signals.tick
  local before = 0
  for _ in pairs(cell.subscribers) do before = before + 1 end
  assert(before == 3, "one effect per item, got " .. before)

  instance.scope.items = { 1 }
  local after = 0
  for _ in pairs(cell.subscribers) do after = after + 1 end
  assert(after == 1, "the old items' effects were disposed, got " .. after)

  instance:destroy()
  local disposed = 0
  for _ in pairs(cell.subscribers) do disposed = disposed + 1 end
  assert(disposed == 0, "destroying the component disposed the rest")
  assert(signal ~= nil)
end

return T
