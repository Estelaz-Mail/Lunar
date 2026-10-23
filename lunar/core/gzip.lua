local gzip = {}

local WINDOW = 32768
local MIN_MATCH = 3
local MAX_MATCH = 258

local LENGTH_BASE = {
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
  67, 83, 99, 115, 131, 163, 195, 227, 258,
}
local LENGTH_EXTRA = {
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
  4, 4, 4, 4, 5, 5, 5, 5, 0,
}
local DISTANCE_BASE = {
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513,
  769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
}
local DISTANCE_EXTRA = {
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
  9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
}

local crc_table = nil

local function crc32(text)
  if not crc_table then
    crc_table = {}
    for index = 0, 255 do
      local value = index
      for _ = 1, 8 do
        if value & 1 == 1 then
          value = 0xEDB88320 ~ (value >> 1)
        else
          value = value >> 1
        end
      end
      crc_table[index] = value
    end
  end
  local crc = 0xFFFFFFFF
  for index = 1, #text do
    crc = crc_table[(crc ~ text:byte(index)) & 0xFF] ~ (crc >> 8)
  end
  return (crc ~ 0xFFFFFFFF) & 0xFFFFFFFF
end

local Writer = {}
Writer.__index = Writer

local function writer()
  return setmetatable({ parts = {}, bits = 0, width = 0 }, Writer)
end

function Writer:put(value, width)
  self.bits = self.bits | (value << self.width)
  self.width = self.width + width
  while self.width >= 8 do
    self.parts[#self.parts + 1] = string.char(self.bits & 0xFF)
    self.bits = self.bits >> 8
    self.width = self.width - 8
  end
end

function Writer:code(value, width)
  local reversed = 0
  for _ = 1, width do
    reversed = (reversed << 1) | (value & 1)
    value = value >> 1
  end
  self:put(reversed, width)
end

function Writer:align()
  if self.width > 0 then
    self.parts[#self.parts + 1] = string.char(self.bits & 0xFF)
    self.bits = 0
    self.width = 0
  end
end

function Writer:done()
  self:align()
  return table.concat(self.parts)
end

local function literal(out, byte)
  if byte < 144 then
    out:code(0x30 + byte, 8)
  else
    out:code(0x190 + byte - 144, 9)
  end
end

local function length_code(length)
  local index = 29
  while LENGTH_BASE[index] > length do index = index - 1 end
  return index
end

local function distance_code(distance)
  local index = 30
  while DISTANCE_BASE[index] > distance do index = index - 1 end
  return index
end

local function emit_symbol(out, symbol)
  if symbol < 280 then
    out:code(symbol - 256, 7)
  else
    out:code(0xC0 + symbol - 280, 8)
  end
end

local function emit_match(out, length, distance)
  local index = length_code(length)
  emit_symbol(out, 256 + index)
  local extra = LENGTH_EXTRA[index]
  if extra > 0 then out:put(length - LENGTH_BASE[index], extra) end

  local slot = distance_code(distance)
  out:code(slot - 1, 5)
  local distance_bits = DISTANCE_EXTRA[slot]
  if distance_bits > 0 then out:put(distance - DISTANCE_BASE[slot], distance_bits) end
end

function gzip.deflate(text, options)
  options = options or {}
  local effort = options.effort or 16
  local out = writer()
  out:put(1, 1)
  out:put(1, 2)

  local size = #text
  local byte = string.byte
  local head, chain = {}, {}
  local position = 1

  while position <= size do
    local length, distance = 0, 0

    if position + MIN_MATCH - 1 <= size then
      local key = byte(text, position) * 65536 + byte(text, position + 1) * 256
        + byte(text, position + 2)
      local candidate = head[key]
      local limit = position - WINDOW
      local tries = effort

      while candidate and candidate > limit and tries > 0 do
        if byte(text, candidate + length) == byte(text, position + length) then
          local run = 0
          while run < MAX_MATCH and position + run <= size
            and byte(text, candidate + run) == byte(text, position + run) do
            run = run + 1
          end
          if run > length then
            length, distance = run, position - candidate
            if run >= MAX_MATCH then break end
          end
        end
        candidate = chain[candidate]
        tries = tries - 1
      end

      chain[position] = head[key]
      head[key] = position
    end

    if length >= MIN_MATCH then
      emit_match(out, length, distance)
      for step = position + 1, position + length - 1 do
        if step + MIN_MATCH - 1 <= size then
          local key = byte(text, step) * 65536 + byte(text, step + 1) * 256
            + byte(text, step + 2)
          chain[step] = head[key]
          head[key] = step
        end
      end
      position = position + length
    else
      literal(out, byte(text, position))
      position = position + 1
    end
  end

  emit_symbol(out, 256)
  return out:done()
end

function gzip.compress(text, options)
  return "\31\139\8\0\0\0\0\0\0\255"
    .. gzip.deflate(text, options)
    .. string.pack("<I4I4", crc32(text), #text & 0xFFFFFFFF)
end

gzip.crc32 = crc32

return gzip
