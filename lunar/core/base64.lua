local base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for index = 1, #ALPHABET do DECODE[ALPHABET:sub(index, index)] = index - 1 end

local function sextet(value)
  return ALPHABET:sub(value + 1, value + 1)
end

function base64.encode(bytes)
  local parts = {}
  local length = #bytes
  local position = 1
  while position + 2 <= length do
    local a, b, c = bytes:byte(position, position + 2)
    local triple = (a << 16) | (b << 8) | c
    parts[#parts + 1] = sextet(triple >> 18) .. sextet((triple >> 12) & 63)
      .. sextet((triple >> 6) & 63) .. sextet(triple & 63)
    position = position + 3
  end
  local remaining = length - position + 1
  if remaining == 1 then
    local triple = bytes:byte(position) << 16
    parts[#parts + 1] = sextet(triple >> 18) .. sextet((triple >> 12) & 63) .. "=="
  elseif remaining == 2 then
    local a, b = bytes:byte(position, position + 1)
    local triple = (a << 16) | (b << 8)
    parts[#parts + 1] = sextet(triple >> 18) .. sextet((triple >> 12) & 63)
      .. sextet((triple >> 6) & 63) .. "="
  end
  return table.concat(parts)
end

function base64.decode(text)
  local bits, count = 0, 0
  local out = {}
  for index = 1, #text do
    local char = text:sub(index, index)
    if char ~= "=" and not char:match("%s") then
      local value = DECODE[char]
      if value == nil then return nil end
      bits = (bits << 6) | value
      count = count + 6
      if count >= 8 then
        count = count - 8
        out[#out + 1] = string.char((bits >> count) & 0xff)
      end
    end
  end
  return table.concat(out)
end

return base64
