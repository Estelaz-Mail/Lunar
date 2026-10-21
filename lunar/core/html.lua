--- Escaping, and the two places markup is assembled by hand.
--
-- Everything a template interpolates goes through `escape`. The only way past
-- it is `{@html expr}`, which is the whole point of having a separate syntax
-- for it: the call site says it is markup.

local html = {}

local ESCAPES = {
  ["&"] = "&amp;",
  ["<"] = "&lt;",
  [">"] = "&gt;",
  ['"'] = "&quot;",
  ["'"] = "&#39;",
}

function html.escape(value)
  if value == nil then return "" end
  return (tostring(value):gsub("[&<>\"']", ESCAPES))
end

--- The text an interpolation produces. `nil` and `false` render as nothing,
-- the way an absent value should, rather than as the word "nil".
function html.text(value)
  if value == nil or value == false then return "" end
  return html.escape(value)
end

--- The value an interpolation puts in the DOM, unescaped: the browser half
-- sets `textContent`, which escapes by construction.
function html.plain(value)
  if value == nil or value == false then return "" end
  return tostring(value)
end

--- One attribute, with the boolean behaviour of HTML: `false` and `nil` render
-- nothing at all, `true` renders the empty value.
--
-- `true` is written `name=""` rather than as a bare `name` on purpose. The two
-- are the same attribute to a browser, but a DOM node can only hold the empty
-- string, so writing it this way is what makes the server's markup and the
-- browser's tree compare equal — which is how the two renderers are tested
-- against each other.
function html.attr(name, value)
  if value == nil or value == false then return "" end
  if value == true then value = "" end
  return string.format(' %s="%s"', name, html.escape(value))
end

--- The value of a `class` attribute: whatever the template wrote, plus the
-- `class:name` directives that are on, plus the component's scoping class.
-- Conditions are `{ {"name", truthy}, ... }`, which is what the generator
-- emits for both renderers.
function html.class_list(base, conditions, scope_class)
  local classes = {}
  if base ~= nil and base ~= "" and base ~= false then
    classes[#classes + 1] = tostring(base)
  end
  for _, condition in ipairs(conditions or {}) do
    if condition[2] then classes[#classes + 1] = condition[1] end
  end
  if scope_class then classes[#classes + 1] = scope_class end
  if #classes == 0 then return nil end
  return table.concat(classes, " ")
end

--- `style` from a base string and a list of declarations, which is what
-- `style:prop` compiles into.
function html.style_list(base, declarations)
  local parts = {}
  if base ~= nil and base ~= "" and base ~= false then
    local trimmed = tostring(base):gsub(";%s*$", "")
    parts[#parts + 1] = trimmed
  end
  for _, declaration in ipairs(declarations or {}) do
    if declaration.value ~= nil and declaration.value ~= false then
      parts[#parts + 1] = declaration.name .. ": " .. tostring(declaration.value)
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "; ")
end

--- The attribute names of a spread, sorted, and only the ones that are names
-- an attribute may have. Shared by both renderers so a spread comes out in the
-- same order on the server and in the browser.
function html.attribute_names(values, skip)
  local names = {}
  for name in pairs(values) do
    name = tostring(name)
    if not (skip and skip[name]) and name:match("^[%a_:][%w_%-%.:]*$") then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

-- The named references a template is likely to contain. HTML has a couple of
-- thousand; these are the ones worth carrying, and an unknown name is left
-- alone rather than guessed at.
local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'",
  nbsp = "\u{00a0}", copy = "\u{00a9}", reg = "\u{00ae}", trade = "\u{2122}",
  hellip = "\u{2026}", mdash = "\u{2014}", ndash = "\u{2013}",
  laquo = "\u{00ab}", raquo = "\u{00bb}", times = "\u{00d7}", divide = "\u{00f7}",
  deg = "\u{00b0}", plusmn = "\u{00b1}", frac12 = "\u{00bd}", middot = "\u{00b7}",
  bull = "\u{2022}", dagger = "\u{2020}", euro = "\u{20ac}", pound = "\u{00a3}",
  larr = "\u{2190}", rarr = "\u{2192}", uarr = "\u{2191}", darr = "\u{2193}",
  check = "\u{2713}", cross = "\u{2717}", ellip = "\u{2026}",
}

--- Turns the references in a piece of template text into the characters they
-- stand for.
--
-- The compiler does this once, at compile time, because the two renderers put
-- that text in different places: the server writes markup, where `&lt;` is a
-- `<`, and the browser writes a text node, where it has to be a real `<` or
-- the page shows the five characters. Decoding here and escaping on the way
-- out is what makes the two agree.
function html.decode(text)
  if not text:find("&", 1, true) then return text end
  return (text:gsub("&(#?[%w]+);", function(reference)
    if reference:sub(1, 1) == "#" then
      local digits = reference:sub(2)
      local code = digits:match("^[xX](%x+)$") and tonumber(digits:sub(2), 16)
        or tonumber(digits)
      if code and code > 0 and code <= 0x10ffff then return utf8.char(code) end
      return nil
    end
    return ENTITIES[reference]
  end))
end

html.ENTITIES = ENTITIES

-- The elements that never have a closing tag. A template that writes children
-- into one is a template that would produce markup the browser reparses
-- differently from the server, so the compiler refuses it.
html.VOID_ELEMENTS = {
  area = true, base = true, br = true, col = true, embed = true, hr = true,
  img = true, input = true, link = true, meta = true, param = true,
  source = true, track = true, wbr = true,
}

-- Elements whose content is text, not markup: a `<` inside one is a `<`.
html.RAW_TEXT_ELEMENTS = { script = true, style = true, textarea = true, title = true }

return html
