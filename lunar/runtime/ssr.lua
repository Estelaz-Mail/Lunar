local html = require("lunar.core.html")

local ssr = {}

ssr.escape = html.escape
ssr.text = html.text

function ssr.raw(value)
  if value == nil or value == false then return "" end
  return tostring(value)
end

ssr.attr = html.attr

function ssr.spread(value, skip)
  if type(value) ~= "table" then return "" end
  local out = {}
  for _, name in ipairs(html.attribute_names(value, skip)) do
    out[#out + 1] = html.attr(name, value[name])
  end
  return table.concat(out)
end

function ssr.class_attr(base, conditions, scope_class)
  local value = html.class_list(base, conditions, scope_class)
  if value == nil then return "" end
  return html.attr("class", value)
end

function ssr.style_attr(base, declarations)
  local value = html.style_list(base, declarations)
  if value == nil then return "" end
  return html.attr("style", value)
end

function ssr.list(value)
  if value == nil then return {} end
  if type(value) ~= "table" then
    error("lunar: {#each} needs a list, got a " .. type(value), 0)
  end
  return value
end

function ssr.is_empty(value)
  if value == nil then return true end
  if type(value) == "table" then return #value == 0 end
  return false
end

return ssr
