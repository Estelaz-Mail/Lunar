local formatter = {}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_closing(line)
  return line:match("^</") or line:match("^{/") or line:match("^{:")
end

local function is_opening(line)
  if line:match("^<!") or line:match("^<%?%") then return false end
  if line:match("^</") or line:match("^{/") or line:match("^{:") then return false end
  if line:find("</", 1, true) or line:find("{/", 1, true) then return false end
  if line:match("^%b{}$") then return false end
  if line:match("/>%s*$") then return false end
  return line:match(">%s*$") ~= nil or line:match("^%{#") ~= nil
end

local function format_template(source)
  local output = {}
  local indent = 0
  local mode = "template"

  for line in (source .. "\n"):gmatch("(.-)\n") do
    local value = trim(line:gsub("\r$", ""))
    if value == "" then
      if #output == 0 or output[#output] ~= "" then output[#output + 1] = "" end
    elseif value == "<script>" or value == "<style>" then
      output[#output + 1] = string.rep("  ", indent) .. value
      mode = value:sub(2, -2)
    elseif value == "</script>" or value == "</style>" then
      mode = "template"
      output[#output + 1] = string.rep("  ", indent) .. value
    elseif mode ~= "template" then
      output[#output + 1] = line:gsub("\r$", ""):gsub("%s+$", "")
    else
      if is_closing(value) then indent = math.max(0, indent - 1) end
      output[#output + 1] = string.rep("  ", indent) .. value
      if is_opening(value) then indent = indent + 1 end
    end
  end

  while #output > 0 and output[#output] == "" do table.remove(output) end
  return table.concat(output, "\n") .. "\n"
end

function formatter.format(source)
  assert(type(source) == "string", "lunar formatter expects source text")
  return format_template(source:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

return formatter
