local encode = {}

encode.MAGIC = "\0asm\1\0\0\0"

encode.TYPES = {
  i32 = 0x7f, i64 = 0x7e, f32 = 0x7d, f64 = 0x7c,
  funcref = 0x70, externref = 0x6f,
}

encode.SECTIONS = {
  type = 1, import = 2, ["function"] = 3, table = 4, memory = 5, global = 6,
  export = 7, start = 8, element = 9, code = 10, data = 11,
}

function encode.unsigned(value)
  value = math.tointeger(value)
  if value == nil or value < 0 then
    error("lunar: an unsigned LEB128 wants a whole number that is not negative", 2)
  end
  local out = {}
  repeat
    local byte = value & 0x7f
    value = value >> 7
    if value ~= 0 then byte = byte | 0x80 end
    out[#out + 1] = string.char(byte)
  until value == 0
  return table.concat(out)
end

function encode.signed(value)
  value = math.tointeger(value)
  if value == nil then error("lunar: a signed LEB128 wants a whole number", 2) end
  local out = {}
  while true do
    local byte = value & 0x7f
    value = value // 128
    local sign_bit = (byte & 0x40) ~= 0
    if (value == 0 and not sign_bit) or (value == -1 and sign_bit) then
      out[#out + 1] = string.char(byte)
      return table.concat(out)
    end
    out[#out + 1] = string.char(byte | 0x80)
  end
end

function encode.float(value)
  return string.pack("<d", value + 0.0)
end

function encode.name(text)
  return encode.unsigned(#text) .. text
end

function encode.vector(items)
  return encode.unsigned(#items) .. table.concat(items)
end

function encode.value_type(name)
  local byte = encode.TYPES[name]
  if not byte then error("lunar: " .. tostring(name) .. " is not a wasm type", 2) end
  return string.char(byte)
end

function encode.value_types(names)
  local out = {}
  for index, name in ipairs(names) do out[index] = encode.value_type(name) end
  return encode.vector(out)
end

function encode.function_type(parameters, results)
  return "\x60" .. encode.value_types(parameters) .. encode.value_types(results)
end

function encode.limits(minimum, maximum)
  if maximum then
    return "\x01" .. encode.unsigned(minimum) .. encode.unsigned(maximum)
  end
  return "\x00" .. encode.unsigned(minimum)
end

function encode.section(id, payload)
  if payload == "" then return "" end
  return string.char(id) .. encode.unsigned(#payload) .. payload
end

return encode
