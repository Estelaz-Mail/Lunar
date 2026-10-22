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

function html.text(value)
  if value == nil or value == false then return "" end
  return html.escape(value)
end

function html.plain(value)
  if value == nil or value == false then return "" end
  return tostring(value)
end

function html.attr(name, value)
  if value == nil or value == false then return "" end
  if value == true then value = "" end
  return string.format(' %s="%s"', name, html.escape(value))
end

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

html.VOID_ELEMENTS = {
  area = true, base = true, br = true, col = true, embed = true, hr = true,
  img = true, input = true, link = true, meta = true, param = true,
  source = true, track = true, wbr = true,
}

html.RAW_TEXT_ELEMENTS = { script = true, style = true, textarea = true, title = true }

return html
