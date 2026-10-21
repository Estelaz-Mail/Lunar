--- Component styles, scoped.
--
-- A component's `<style>` applies to that component and nothing else, which is
-- the whole reason a style block belongs in the same file as the markup. There
-- is no shadow DOM involved: every element the component renders gets a class
-- of its own (`l-1a2b3c4d`), and every selector here is rewritten to require
-- it. `h1 { }` becomes `h1.l-1a2b3c4d { }`.
--
-- `:global(...)` opts out, for the few rules that really are about the page:
-- `:global(body) { }` comes out as `body { }`.
--
-- The rewriter is a scanner, not a CSS parser. It knows blocks, strings,
-- comments and at-rules, which is everything it needs to find a selector list;
-- what is inside a declaration it never looks at.

local util = require("lunar.core.util")

local css = {}

-- At-rules whose body is more rules, so the selectors inside are scoped too.
local NESTED_AT_RULES = { media = true, supports = true, container = true, layer = true }
-- Every other at-rule keeps its body verbatim: `@keyframes from { }` must not
-- become `from.l-1a2b3c4d { }`, which would never match anything.

--- Splits a selector list on the commas that are not inside brackets.
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

--- The position where the last compound selector of a complex one begins.
-- `ul > li.item:hover` has its last compound at `li.item:hover`.
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

--- Where the class goes inside a compound: before the first pseudo-class or
-- pseudo-element, so `a:hover` scopes the `a` and not the `:hover`.
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

  -- `:global(...)` anywhere in the selector means the author has taken
  -- responsibility for it; it is unwrapped and left alone.
  if body:find(":global%s*%(") then
    local unwrapped = body:gsub(":global%s*%((.-)%)", "%1")
    return leading .. unwrapped .. trailing
  end

  local start = last_compound_start(body)
  local compound = body:sub(start)
  -- A trailing combinator (`.a >`) has no compound to scope; scope the one
  -- before it instead by leaving the selector alone.
  if compound == "" then return leading .. body .. trailing end

  local at = insertion_point(compound)
  local scoped = compound:sub(1, at - 1) .. "." .. class .. compound:sub(at)
  return leading .. body:sub(1, start - 1) .. scoped .. trailing
end

--- Rewrites a block of rules. `source` is everything between a pair of braces,
-- or the whole stylesheet at the top level.
local function scope_block(source, class, out)
  local position = 1
  local length = #source

  while position <= length do
    -- Find the start of the next rule: everything up to the next `{` is a
    -- prelude, unless a comment or a `;`-terminated at-rule comes first.
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
        -- A statement at-rule: `@import`, `@charset`. Copied as it stands.
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

    -- Find the matching close brace.
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

--- The class a component's elements carry, derived from its path and its
-- styles, so two components never collide and the same component always gets
-- the same class.
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
