local util = require("lunar.core.util")

local sfc = {}

local function line_of(source, position)
  local line = 1
  for _ in source:sub(1, position - 1):gmatch("\n") do line = line + 1 end
  return line
end

local function blank(text)
  return (text:gsub("[^\n]", ""))
end

local function extract(source, tag)
  local open_start, open_stop = source:find("<" .. tag .. "%f[%s/>]")
  if not open_start then return nil, nil, source end

  local attrs_stop = source:find(">", open_stop)
  if not attrs_stop then
    error(string.format("lunar: <%s> is never closed", tag), 0)
  end
  local attributes = source:sub(open_stop + 1, attrs_stop - 1)
  if attributes:find("/%s*$") then
    return nil, nil,
      source:sub(1, open_start - 1) .. blank(source:sub(open_start, attrs_stop))
        .. source:sub(attrs_stop + 1)
  end

  local close_start, close_stop = source:find("</" .. tag .. "%s*>", attrs_stop)
  if not close_start then
    error(string.format("lunar: <%s> is never closed", tag), 0)
  end

  local body = source:sub(attrs_stop + 1, close_start - 1)
  local rest = source:sub(1, open_start - 1)
    .. blank(source:sub(open_start, close_stop))
    .. source:sub(close_stop + 1)
  return body, line_of(source, attrs_stop + 1), rest, util.trim(attributes)
end

function sfc.split(source, filename)
  local name = filename or "component"
  local ok, result = pcall(function()
    local script, script_line, without_script, script_attributes = extract(source, "script")
    local style, style_line, template, style_attributes = extract(without_script, "style")
    return {
      script = script or "",
      script_line = script_line,
      script_attributes = script_attributes or "",
      style = style or "",
      style_line = style_line,
      style_attributes = style_attributes or "",
      template = template,
    }
  end)
  if not ok then
    error((tostring(result):gsub("^lunar: ", "lunar: " .. name .. ": ")), 0)
  end

  if result.template:find("<script%f[%s/>]") then
    error(string.format("lunar: %s: a component has one <script>, at the top level", name), 0)
  end

  return result
end

return sfc
