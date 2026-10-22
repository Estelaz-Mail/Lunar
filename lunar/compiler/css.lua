local util = require("lunar.core.util")

local css = {}

local NESTED_AT_RULES = { media = true, supports = true, container = true, layer = true }

local function split_selectors(list)
  local out = {}
  local depth = 0
  local start = 1
  local index = 1
  while index <= #list do
    local char = list:sub(index, index)
    if char == "(" or char == "[" then
      depth = depth + 1
    elseif char == ")" or char == "]" then
      depth = depth - 1
    elseif char == "," and depth == 0 then
      out[#out + 1] = list:sub(start, index - 1)
      start = index + 1
    elseif char == '"' or char == "'" then
      local stop = list:find(char, index + 1, true) or #list
      index = stop
    end
    index = index + 1
  end
  out[#out + 1] = list:sub(start)
  return out
end

local function last_compound_start(selector)
  local depth = 0
  local position = #selector
  local start = 1
  while position >= 1 do
    local char = selector:sub(position, position)
    if char == ")" or char == "]" then
      depth = depth + 1
    elseif char == "(" or char == "[" then
      depth = depth - 1
    elseif depth == 0 and (char == " " or char == "\t" or char == "\n"
      or char == ">" or char == "+" or char == "~") then
      start = position + 1
      break
    end
    position = position - 1
  end
  return start
end

local function insertion_point(compound)
  local depth = 0
  for index = 1, #compound do
    local char = compound:sub(index, index)
    if char == "(" or char == "[" then
      depth = depth + 1
    elseif char == ")" or char == "]" then
      depth = depth - 1
    elseif char == ":" and depth == 0 then
      return index
    end
  end
  return #compound + 1
end

local function scope_selector(selector, class)
  local leading = selector:match("^%s*") or ""
  local trailing = selector:match("%s*$") or ""
  local body = util.trim(selector)
  if body == "" then return selector end

  if body:find(":global%s*%(") then
    local unwrapped = body:gsub(":global%s*%((.-)%)", "%1")
    return leading .. unwrapped .. trailing
  end

  local start = last_compound_start(body)
  local compound = body:sub(start)
  if compound == "" then return leading .. body .. trailing end

  local at = insertion_point(compound)
  local scoped = compound:sub(1, at - 1) .. "." .. class .. compound:sub(at)
  return leading .. body:sub(1, start - 1) .. scoped .. trailing
end

local function scope_block(source, class, out)
  local position = 1
  local length = #source

  while position <= length do
    local prelude_start = position
    local index = position
    local depth = 0
    local brace

    while index <= length do
      local char = source:sub(index, index)
      if char == "/" and source:sub(index + 1, index + 1) == "*" then
        local stop = source:find("*/", index + 2, true)
        index = (stop or length) + 2
      elseif char == '"' or char == "'" then
        local stop = source:find(char, index + 1, true) or length
        index = stop + 1
      elseif char == "(" or char == "[" then
        depth = depth + 1
        index = index + 1
      elseif char == ")" or char == "]" then
        depth = depth - 1
        index = index + 1
      elseif char == "{" and depth == 0 then
        brace = index
        break
      elseif char == ";" and depth == 0 then
        out[#out + 1] = source:sub(prelude_start, index)
        position = index + 1
        prelude_start = position
        index = position
      else
        index = index + 1
      end
    end

    if not brace then
      out[#out + 1] = source:sub(prelude_start)
      return
    end

    local body_start = brace + 1
    local body_depth = 1
    local scan = body_start
    while scan <= length and body_depth > 0 do
      local char = source:sub(scan, scan)
      if char == "/" and source:sub(scan + 1, scan + 1) == "*" then
        scan = (source:find("*/", scan + 2, true) or length) + 2
      elseif char == '"' or char == "'" then
        scan = (source:find(char, scan + 1, true) or length) + 1
      else
        if char == "{" then body_depth = body_depth + 1 end
        if char == "}" then body_depth = body_depth - 1 end
        scan = scan + 1
      end
    end
    local body_stop = scan - 2
    local prelude = source:sub(prelude_start, brace - 1)
    local body = source:sub(body_start, body_stop)

    local at_rule = util.trim(prelude):match("^@([%a%-]+)")
    if at_rule then
      out[#out + 1] = prelude .. "{"
      if NESTED_AT_RULES[at_rule] then
        scope_block(body, class, out)
      else
        out[#out + 1] = body
      end
      out[#out + 1] = "}"
    else
      local selectors = {}
      for _, selector in ipairs(split_selectors(prelude)) do
        selectors[#selectors + 1] = scope_selector(selector, class)
      end
      out[#out + 1] = table.concat(selectors, ",") .. "{" .. body .. "}"
    end
    position = scan
  end
end

function css.scope_class(identity)
  return "l-" .. util.hash(identity)
end

function css.scope(source, class)
  if util.trim(source or "") == "" then return "" end
  local out = {}
  scope_block(source, class, out)
  return table.concat(out)
end

css.split_selectors = split_selectors

return css
