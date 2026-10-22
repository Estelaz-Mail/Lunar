local minify = {}

local function long_bracket(source, position)
  local level = source:match("^%[(=*)%[", position)
  if not level then return nil end
  local open = "[" .. level .. "["
  local close = "]" .. level .. "]"
  local stop = source:find(close, position + #open, true)
  if not stop then return #source + 1, source:sub(position) end
  return stop + #close, source:sub(position, stop + #close - 1)
end

function minify.lua_source(source)
  if type(source) ~= "string" then return source end

  local out = {}
  local size = #source
  local position = 1
  local space = false
  local newline = false

  local function emit(text)
    if #out > 0 then
      if newline then
        out[#out + 1] = "\n"
      elseif space then
        out[#out + 1] = " "
      end
    end
    space, newline = false, false
    out[#out + 1] = text
  end

  while position <= size do
    local char = source:sub(position, position)

    if char == "\n" then
      newline = true
      position = position + 1
    elseif char == " " or char == "\t" or char == "\r" or char == "\f" or char == "\v" then
      space = true
      position = position + 1
    elseif source:sub(position, position + 1) == "--" then
      local closing = long_bracket(source, position + 2)
      if closing then
        position = closing
      else
        position = source:find("\n", position + 2, true) or (size + 1)
      end
    elseif char == '"' or char == "'" then
      local stop = position + 1
      while stop <= size do
        local inner = source:sub(stop, stop)
        if inner == "\\" then
          stop = stop + 2
        elseif inner == char then
          stop = stop + 1
          break
        elseif inner == "\n" then
          break
        else
          stop = stop + 1
        end
      end
      emit(source:sub(position, stop - 1))
      position = stop
    elseif char == "[" then
      local closing, text = long_bracket(source, position)
      if closing then
        emit(text)
        position = closing
      else
        emit(char)
        position = position + 1
      end
    else
      local stop = source:find("[%s%-\"'%[]", position + 1) or (size + 1)
      emit(source:sub(position, stop - 1))
      position = stop
    end
  end

  if newline and #out > 0 then out[#out + 1] = "\n" end
  return table.concat(out)
end

return minify
