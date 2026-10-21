--- The code generator.
--
-- One tree in, two functions out: `ssr`, which appends strings to a table, and
-- `client`, which builds nodes through a DOM adapter. They are written side by
-- side, from the same walk, so a feature cannot exist in one renderer and not
-- the other — and `spec/render_spec.lua` renders every fixture both ways and
-- compares the markup.
--
-- The generated module is plain Lua, meant to be read: `bin/lunar compile`
-- prints it. Every name the generator introduces starts with `__`, so it
-- cannot collide with a name from the component.
--
-- Line numbers: the module pads itself so the `<script>` body lands on the
-- line it occupies in the `.lunar` file. A runtime error in a script therefore
-- points at the component. The generated template code comes after and has
-- line numbers of its own, which is why template *expressions* are checked at
-- compile time instead.

local html = require("lunar.core.html")
local util = require("lunar.core.util")

local codegen = {}

local Writer = {}
Writer.__index = Writer

local function writer(options)
  return setmetatable({
    lines = {},
    indent = options and options.indent or 1,
    pending = {},
    counter = options and options.counter or { n = 0 },
    out = "__out",
  }, Writer)
end

function Writer:id(prefix)
  self.counter.n = self.counter.n + 1
  return string.format("__%s%d", prefix, self.counter.n)
end

function Writer:line(code)
  self:flush()
  self.lines[#self.lines + 1] = string.rep("  ", self.indent) .. code
end

--- Static markup is buffered and written as one assignment, so a template of
-- plain HTML compiles to one string and not forty.
function Writer:static(text)
  if text == "" then return end
  self.pending[#self.pending + 1] = text
end

function Writer:flush()
  if #self.pending == 0 then return end
  local text = table.concat(self.pending)
  self.pending = {}
  self.lines[#self.lines + 1] = string.format("%s%s[#%s + 1] = %s",
    string.rep("  ", self.indent), self.out, self.out, string.format("%q", text))
end

function Writer:dynamic(expression)
  self:flush()
  self.lines[#self.lines + 1] = string.format("%s%s[#%s + 1] = %s",
    string.rep("  ", self.indent), self.out, self.out, expression)
end

function Writer:push() self.indent = self.indent + 1 end
function Writer:pop() self.indent = self.indent - 1 end

function Writer:body()
  self:flush()
  return table.concat(self.lines, "\n")
end

-- Attributes --------------------------------------------------------------------

--- The Lua expression for an attribute value written as `"a {b} c"`.
local function parts_expression(parts)
  if #parts == 1 and parts[1].kind == "text" then
    return string.format("%q", parts[1].value)
  end
  local pieces = {}
  for _, part in ipairs(parts) do
    if part.kind == "text" then
      pieces[#pieces + 1] = string.format("%q", part.value)
    else
      pieces[#pieces + 1] = string.format("__plain(%s)", part.code)
    end
  end
  return "(" .. table.concat(pieces, " .. ") .. ")"
end

--- Splits an element's attributes into the shapes the generators need. `class`
-- and `style` are pulled out because the directives have to merge into them.
local function sort_attributes(node, scope_class)
  local plain, events, binds, spreads = {}, {}, {}, {}
  local class_conditions, style_declarations = {}, {}
  local class_value, style_value
  local names = {}

  for _, attribute in ipairs(node.attributes or {}) do
    local kind = attribute.type
    if kind == "event" then
      events[#events + 1] = attribute
    elseif kind == "bind" then
      binds[#binds + 1] = attribute
    elseif kind == "spread" then
      spreads[#spreads + 1] = attribute
    elseif kind == "class" then
      class_conditions[#class_conditions + 1] = attribute
    elseif kind == "style" then
      style_declarations[#style_declarations + 1] = attribute
    else
      names[attribute.name] = true
      local value
      if kind == "parts" then
        value = { dynamic = #attribute.parts > 1 or attribute.parts[1].kind ~= "text",
          code = parts_expression(attribute.parts),
          literal = (#attribute.parts == 1 and attribute.parts[1].kind == "text")
            and attribute.parts[1].value or nil }
      elseif kind == "expr" then
        value = { dynamic = true, code = attribute.code }
      else
        value = { dynamic = false, literal = true, boolean = true }
      end
      if attribute.name == "class" then
        class_value = value
      elseif attribute.name == "style" then
        style_value = value
      else
        plain[#plain + 1] = { name = attribute.name, value = value }
      end
    end
  end

  local needs_class = class_value ~= nil or #class_conditions > 0 or scope_class ~= nil
  return {
    plain = plain, events = events, binds = binds, spreads = spreads,
    class_conditions = class_conditions, style_declarations = style_declarations,
    class_value = class_value, style_value = style_value,
    needs_class = needs_class, names = names,
  }
end

local function value_expression(value)
  if value == nil then return "nil" end
  if value.boolean then return "true" end
  if value.literal ~= nil and not value.dynamic then return string.format("%q", value.literal) end
  return value.code
end

local function conditions_table(conditions)
  local pieces = {}
  for _, condition in ipairs(conditions) do
    pieces[#pieces + 1] = string.format("{%q, %s}", condition.name, condition.code)
  end
  return "{" .. table.concat(pieces, ", ") .. "}"
end

local function declarations_table(declarations)
  local pieces = {}
  for _, declaration in ipairs(declarations) do
    pieces[#pieces + 1] = string.format("{name = %q, value = %s}",
      declaration.name, declaration.code)
  end
  return "{" .. table.concat(pieces, ", ") .. "}"
end

-- The server renderer -------------------------------------------------------------

local ssr_nodes

local function ssr_element(node, w, options)
  local scope_class = options.scope_class
  local parts = sort_attributes(node, scope_class)

  w:static("<" .. node.tag)

  for _, attribute in ipairs(parts.plain) do
    if attribute.value.boolean then
      w:static(" " .. attribute.name)
    elseif not attribute.value.dynamic then
      w:static(html.attr(attribute.name, attribute.value.literal))
    else
      w:dynamic(string.format("__attr(%q, %s)", attribute.name, attribute.value.code))
    end
  end

  for _, spread in ipairs(parts.spreads) do
    local skip = {}
    for name in pairs(parts.names) do skip[#skip + 1] = string.format("[%q] = true", name) end
    w:dynamic(string.format("__spread(%s, {%s})", spread.code, table.concat(skip, ", ")))
  end

  if parts.needs_class then
    local base = parts.class_value
    local static_only = (base == nil or not base.dynamic) and #parts.class_conditions == 0
    if static_only then
      local names = {}
      if base and base.literal then names[#names + 1] = base.literal end
      if scope_class then names[#names + 1] = scope_class end
      if #names > 0 then w:static(html.attr("class", table.concat(names, " "))) end
    else
      w:dynamic(string.format("__class(%s, %s, %s)",
        value_expression(base), conditions_table(parts.class_conditions),
        scope_class and string.format("%q", scope_class) or "nil"))
    end
  end

  if parts.style_value or #parts.style_declarations > 0 then
    local base = parts.style_value
    if base and not base.dynamic and #parts.style_declarations == 0 then
      w:static(html.attr("style", base.literal))
    else
      w:dynamic(string.format("__style(%s, %s)",
        value_expression(base), declarations_table(parts.style_declarations)))
    end
  end

  -- A binding's value is the element's value on the server; the two-way half
  -- only exists in a browser.
  for _, bind in ipairs(parts.binds) do
    if bind.name == "checked" then
      w:dynamic(string.format("__attr(%q, (%s) and true or false)", "checked", bind.code))
    elseif bind.name == "group" then
      w:dynamic(string.format("__attr(%q, nil)", "value"))
    else
      w:dynamic(string.format("__attr(%q, %s)", bind.name, bind.code))
    end
  end

  w:static(">")

  if node.self_closing then return end

  if node.raw_text then
    -- `<script>` and `<style>` inside a template keep their text verbatim.
    w:static(node.children[1] and node.children[1].value or "")
  else
    ssr_nodes(node.children, w, options)
  end
  w:static("</" .. node.tag .. ">")
end

local function ssr_component(node, w, options)
  local parts = sort_attributes(node, nil)
  if #parts.events > 0 then
    error(string.format("lunar: %s:%d: on: on a component needs a prop: pass the handler as one",
      options.filename, node.line), 0)
  end
  if #parts.binds > 0 then
    error(string.format("lunar: %s:%d: bind: on a component is not part of Lunar",
      options.filename, node.line), 0)
  end

  local props = {}
  for _, attribute in ipairs(parts.plain) do
    props[#props + 1] = string.format("[%q] = %s", attribute.name, value_expression(attribute.value))
  end
  if parts.class_value then
    props[#props + 1] = string.format("[%q] = %s", "class", value_expression(parts.class_value))
  end
  local props_table = "{" .. table.concat(props, ", ") .. "}"
  for _, spread in ipairs(parts.spreads) do
    props_table = string.format("__merge(%s, %s)", props_table, spread.code)
  end

  local slot = "nil"
  if #node.children > 0 then
    local inner = writer({ indent = w.indent + 1, counter = w.counter })
    inner.out = "__out"
    ssr_nodes(node.children, inner, options)
    slot = "function(__out)\n" .. inner:body() .. "\n" .. string.rep("  ", w.indent) .. "end"
  end

  w:dynamic(string.format("__rt.render_child(__self, %s, %s, %s)", node.tag, props_table, slot))
end

local function ssr_if(node, w, options)
  for index, branch in ipairs(node.branches) do
    w:line(string.format("%s %s then", index == 1 and "if" or "elseif", branch.test))
    w:push()
    ssr_nodes(branch.children, w, options)
    w:pop()
  end
  if node.else_children then
    w:line("else")
    w:push()
    ssr_nodes(node.else_children, w, options)
    w:pop()
  end
  w:line("end")
end

local function ssr_each(node, w, options)
  local list = w:id("list")
  w:line(string.format("local %s = __list(%s)", list, node.list))
  if node.else_children then
    w:line(string.format("if __empty(%s) then", list))
    w:push()
    ssr_nodes(node.else_children, w, options)
    w:pop()
    w:line("else")
    w:push()
  end
  local index = node.index or w:id("i")
  w:line(string.format("for %s, %s in ipairs(%s) do", index, node.item, list))
  w:push()
  ssr_nodes(node.children, w, options)
  w:pop()
  w:line("end")
  if node.else_children then
    w:pop()
    w:line("end")
  end
end

--- `<lunar:head>`. Its children are hoisted into the document head, where a
-- component's scoping class would be meaningless — nothing styles a `<title>`
-- — so they are generated without one.
local function head_options(options)
  local out = {}
  for key, value in pairs(options) do out[key] = value end
  out.scope_class = nil
  return out
end

local function ssr_head(node, w, options)
  local buffer = w:id("head")
  w:line(string.format("local %s = {}", buffer))
  local previous = w.out
  w.out = buffer
  ssr_nodes(node.children, w, head_options(options))
  w:flush()
  w.out = previous
  w:line(string.format("__self.ctx.head[#__self.ctx.head + 1] = table.concat(%s)", buffer))
end

ssr_nodes = function(nodes, w, options)
  for _, node in ipairs(nodes) do
    local kind = node.kind
    if kind == "text" then
      -- The text was decoded at parse time, so it is escaped here. A `<` an
      -- author wrote as `&lt;` therefore comes back out as `&lt;`, and the
      -- browser renderer's text node holds the one character it stands for.
      w:static(html.escape(node.value))
    elseif kind == "expr" then
      w:dynamic(string.format(node.raw and "__raw(%s)" or "__text(%s)", node.code))
    elseif kind == "element" then
      ssr_element(node, w, options)
    elseif kind == "component" then
      ssr_component(node, w, options)
    elseif kind == "if" then
      ssr_if(node, w, options)
    elseif kind == "each" then
      ssr_each(node, w, options)
    elseif kind == "head" then
      ssr_head(node, w, options)
    elseif kind == "slot" then
      local fallback = "nil"
      if #node.children > 0 then
        local inner = writer({ indent = w.indent + 1, counter = w.counter })
        ssr_nodes(node.children, inner, options)
        fallback = "function(__out)\n" .. inner:body() .. "\n"
          .. string.rep("  ", w.indent) .. "end"
      end
      w:line(string.format("__rt.render_slot(__self, __out, %s)", fallback))
    end
  end
end

-- The browser renderer --------------------------------------------------------------

local client_nodes

local function client_attribute(w, target, name, value)
  if value.boolean then
    w:line(string.format("__d:attr(%s, %q, true)", target, name))
  elseif not value.dynamic then
    w:line(string.format("__d:attr(%s, %q, %q)", target, name, value.literal))
  else
    w:line(string.format("__rt.effect(__self, function() __d:attr(%s, %q, %s) end)",
      target, name, value.code))
  end
end

local function client_element(node, w, options)
  local scope_class = options.scope_class
  local parts = sort_attributes(node, scope_class)
  local target = w:id("e")

  w:line(string.format("local %s = __d:element(%q)", target, node.tag))

  for _, attribute in ipairs(parts.plain) do
    client_attribute(w, target, attribute.name, attribute.value)
  end

  for _, spread in ipairs(parts.spreads) do
    local skip = {}
    for name in pairs(parts.names) do skip[#skip + 1] = string.format("[%q] = true", name) end
    w:line(string.format("__rt.effect(__self, function() __d:spread(%s, %s, {%s}) end)",
      target, spread.code, table.concat(skip, ", ")))
  end

  if parts.needs_class then
    local base = parts.class_value
    local static_only = (base == nil or not base.dynamic) and #parts.class_conditions == 0
    if static_only then
      local names = {}
      if base and base.literal then names[#names + 1] = base.literal end
      if scope_class then names[#names + 1] = scope_class end
      if #names > 0 then
        w:line(string.format("__d:attr(%s, \"class\", %q)", target, table.concat(names, " ")))
      end
    else
      w:line(string.format(
        "__rt.effect(__self, function() __d:attr(%s, \"class\", __class_value(%s, %s, %s)) end)",
        target, value_expression(base), conditions_table(parts.class_conditions),
        scope_class and string.format("%q", scope_class) or "nil"))
    end
  end

  if parts.style_value or #parts.style_declarations > 0 then
    local base = parts.style_value
    if base and not base.dynamic and #parts.style_declarations == 0 then
      w:line(string.format("__d:attr(%s, \"style\", %q)", target, base.literal))
    else
      w:line(string.format(
        "__rt.effect(__self, function() __d:attr(%s, \"style\", __style_value(%s, %s)) end)",
        target, value_expression(base), declarations_table(parts.style_declarations)))
    end
  end

  for _, event in ipairs(parts.events) do
    local modifiers = {}
    for _, modifier in ipairs(event.modifiers or {}) do
      modifiers[#modifiers + 1] = string.format("%q", modifier)
    end
    w:line(string.format(
      "__d:on(%s, %q, function(__event) local __h = %s if __h then return __h(__event) end end, {%s})",
      target, event.name, event.code, table.concat(modifiers, ", ")))
  end

  for _, bind in ipairs(parts.binds) do
    w:line(string.format(
      "__rt.bind(__self, __d, %s, %q, function() return %s end, function(__value) %s = __value end)",
      target, bind.name, bind.code, bind.code))
  end

  if not node.self_closing then
    if node.raw_text then
      w:line(string.format("__d:set_text(%s, %q)", target,
        node.children[1] and node.children[1].value or ""))
    else
      local previous = w.parent
      w.parent = target
      client_nodes(node.children, w, options)
      w.parent = previous
    end
  end

  w:line(string.format("__d:append(%s, %s)", w.parent, target))
end

--- A builder is the body of a block: a function that fills whatever parent it
-- is given, so the same code can build into a fragment or into the document.
local function builder(nodes, w, options, extra_args)
  local inner = writer({ indent = w.indent + 1, counter = w.counter })
  inner.parent = "__parent"
  client_nodes(nodes, inner, options)
  local args = "__parent" .. (extra_args and (", " .. extra_args) or "")
  return string.format("function(%s)\n%s\n%send", args, inner:body(),
    string.rep("  ", w.indent))
end

local function client_if(node, w, options)
  local anchor = w:id("a")
  w:line(string.format("local %s = __d:anchor(%s)", anchor, w.parent))

  local selector = { "function()" }
  for index, branch in ipairs(node.branches) do
    selector[#selector + 1] = string.format("%s (%s) then return %d",
      index == 1 and " if" or " elseif", branch.test, index)
  end
  selector[#selector + 1] = string.format(" else return %d end end",
    node.else_children and (#node.branches + 1) or 0)

  local builders = {}
  for _, branch in ipairs(node.branches) do
    builders[#builders + 1] = builder(branch.children, w, options)
  end
  if node.else_children then
    builders[#builders + 1] = builder(node.else_children, w, options)
  end

  w:line(string.format("__rt.branch(__self, __d, %s, %s, {%s})",
    anchor, table.concat(selector), table.concat(builders, ", ")))
end

local function client_each(node, w, options)
  local anchor = w:id("a")
  w:line(string.format("local %s = __d:anchor(%s)", anchor, w.parent))
  local item_builder = builder(node.children, w, options,
    node.item .. ", " .. (node.index or "__index"))
  local empty = node.else_children and builder(node.else_children, w, options) or "nil"
  w:line(string.format("__rt.each(__self, __d, %s, function() return %s end, %s, %s)",
    anchor, node.list, item_builder, empty))
end

client_nodes = function(nodes, w, options)
  for _, node in ipairs(nodes) do
    local kind = node.kind
    if kind == "text" then
      w:line(string.format("__d:append(%s, __d:text(%q))", w.parent, node.value))
    elseif kind == "expr" then
      if node.raw then
        local anchor = w:id("a")
        w:line(string.format("local %s = __d:anchor(%s)", anchor, w.parent))
        w:line(string.format("__rt.html(__self, __d, %s, function() return %s end)",
          anchor, node.code))
      else
        local text = w:id("t")
        w:line(string.format("local %s = __d:text(\"\")", text))
        w:line(string.format("__d:append(%s, %s)", w.parent, text))
        w:line(string.format("__rt.effect(__self, function() __d:set_text(%s, __plain(%s)) end)",
          text, node.code))
      end
    elseif kind == "element" then
      client_element(node, w, options)
    elseif kind == "component" then
      local parts = sort_attributes(node, nil)
      local props = {}
      for _, attribute in ipairs(parts.plain) do
        props[#props + 1] = string.format("[%q] = %s", attribute.name,
          value_expression(attribute.value))
      end
      if parts.class_value then
        props[#props + 1] = string.format("[%q] = %s", "class",
          value_expression(parts.class_value))
      end
      local props_table = "{" .. table.concat(props, ", ") .. "}"
      for _, spread in ipairs(parts.spreads) do
        props_table = string.format("__merge(%s, %s)", props_table, spread.code)
      end
      local slot = #node.children > 0 and builder(node.children, w, options) or "nil"
      w:line(string.format("__rt.child(__self, __d, %s, %s, function() return %s end, %s)",
        w.parent, node.tag, props_table, slot))
    elseif kind == "if" then
      client_if(node, w, options)
    elseif kind == "each" then
      client_each(node, w, options)
    elseif kind == "head" then
      -- The head is the server's: what is already in the document stays, and
      -- re-rendering it in the browser would duplicate every tag.
      w:line(string.format("__rt.head(__self, __d, %s)",
        builder(node.children, w, head_options(options))))
    elseif kind == "slot" then
      local fallback = #node.children > 0 and builder(node.children, w, options) or "nil"
      w:line(string.format("__rt.slot(__self, __d, %s, %s)", w.parent, fallback))
    end
  end
end

-- Assembly -------------------------------------------------------------------------

local PREAMBLE = table.concat({
  'local __rt = require("lunar.runtime.component")',
  'local __ssr = require("lunar.runtime.ssr")',
  'local __html = require("lunar.core.html")',
  "local __text, __raw, __attr, __spread = __ssr.text, __ssr.raw, __ssr.attr, __ssr.spread",
  "local __class, __style, __list, __empty = __ssr.class_attr, __ssr.style_attr, __ssr.list, __ssr.is_empty",
  "local __class_value, __style_value = __html.class_list, __html.style_list",
  "local __plain, __merge = __html.plain, __rt.merge",
  "local __C = {}",
}, "; ")

--- `options` is `{ script, script_line, css, scope_class, name, path, filename }`.
function codegen.generate(ast, options)
  options = options or {}
  local counter = { n = 0 }

  local ssr_writer = writer({ indent = 1, counter = counter })
  ssr_nodes(ast, ssr_writer, options)

  local client_writer = writer({ indent = 1, counter = counter })
  client_writer.parent = "__p"
  client_nodes(ast, client_writer, options)

  local out = {}

  -- The script is emitted first and padded so its first line lands on the line
  -- it occupies in the component. Everything before it therefore has to fit on
  -- one line, which is why the preamble is written with semicolons.
  local script = options.script or ""
  local script_line = options.script_line or 1
  local header = PREAMBLE .. "; __C.setup = function(_ENV)"
  if script_line > 1 then header = string.rep("\n", script_line - 1) .. header end
  -- Joined with no separator: the script's own leading newline is what moves
  -- its first statement off the header's line. One added here would shift
  -- every line of the script by one, which is exactly the bug this padding
  -- exists to prevent.
  out[#out + 1] = header .. script

  -- The two renderers are closures *inside* the script, not siblings of it.
  -- That is what lets a template see the script's locals — `local Card =
  -- import(...)` is an ordinary upvalue here, exactly as it reads. A component
  -- script therefore cannot `return`, which is the one thing this costs.
  out[#out + 1] = "return function(__out, __self)"
  out[#out + 1] = ssr_writer:body()
  out[#out + 1] = "end, function(__p, __self)"
  out[#out + 1] = "  local __d = __self.dom"
  out[#out + 1] = client_writer:body()
  out[#out + 1] = "end"
  out[#out + 1] = "end"

  out[#out + 1] = string.format("__C.name = %q", options.name or "component")
  out[#out + 1] = string.format("__C.path = %q", options.path or "")
  if options.scope_class then
    out[#out + 1] = string.format("__C.scope_class = %q", options.scope_class)
  end
  if options.css and options.css ~= "" then
    out[#out + 1] = string.format("__C.css = %q", options.css)
  end
  out[#out + 1] = "return __rt.define(__C)"

  return table.concat(out, "\n")
end

return codegen
