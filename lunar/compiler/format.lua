local formatter = {}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_closing(line)
  return line:match("^</") or line:match("^{/")
end

local function is_branch(line)
  return line:match("^{:") ~= nil
end

local function tag_delta(line)
  local delta = 0
  for name in line:gmatch("<([%a][%w:%-]*)%f[%s/>]") do
    local start = line:find("<" .. name, 1, true)
    local stop = start and line:find(">", start, true)
    if stop and line:sub(start, stop):match("/%s*>$") == nil then delta = delta + 1 end
    line = line:sub((stop or #line) + 1)
  end
  for _ in line:gmatch("</[%a][%w:%-]*%s*>") do delta = delta - 1 end
  for _ in line:gmatch("{/[%a][%w_]*%s*}") do delta = delta - 1 end
  for _ in line:gmatch("{%#[%a][^}]*}") do delta = delta + 1 end
  return delta
end

local function format_template(source)
  local output = {}
  local indent = 0
  local mode = "template"
  local open_tag = false

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
      if open_tag then
        if value:match("^>") then
          output[#output + 1] = string.rep("  ", indent) .. value
          open_tag = false
          if value:match("^>%s*$") then indent = indent + 1 end
        else
          output[#output + 1] = string.rep("  ", indent + 1) .. value
        end
        goto continue
      end
      local branch = is_branch(value)
      if is_closing(value) or branch then indent = math.max(0, indent - 1) end
      output[#output + 1] = string.rep("  ", indent) .. value
      if branch then
        indent = indent + 1
      elseif value:match("^<[%a][^>]*$") and not value:match("^<[%a][^>]*%s*/$") then
        open_tag = true
      else
        indent = math.max(0, indent + tag_delta(value))
      end
    end
    ::continue::
  end

  while #output > 0 and output[#output] == "" do table.remove(output) end
  return table.concat(output, "\n") .. "\n"
end

function formatter.format(source)
  assert(type(source) == "string", "lunar formatter expects source text")
  return format_template(source:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

return formatter
