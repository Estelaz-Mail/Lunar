local runtime = {}

runtime.NAME = "runtime"
runtime.DATA_START = 1024
runtime.STRING = 2

runtime.SOURCE = [[
function alloc(size)
  local pointer = mem.load(0)
  local rounded = math.floor((size + 7) / 8) * 8
  local next_free = pointer + rounded
  local limit = mem.size() * 65536
  if next_free > limit then
    local pages = math.floor((next_free - limit) / 65536) + 1
    if mem.grow(pages) < 0 then
      mem.trap()
    end
  end
  mem.store(0, next_free)
  return pointer
end

function length(value)
  if box.is_number(value) then
    mem.trap()
  end
  if box.tag(value) == 3 then
    return mem.load(box.address(value) + 8)
  end
  if box.tag(value) ~= 2 then
    mem.trap()
  end
  return mem.load(box.address(value))
end

local function digits_of(value)
  local count = 1
  local rest = math.floor(value / 10)
  while rest > 0 do
    count = count + 1
    rest = math.floor(rest / 10)
  end
  return count
end

local function number_string(value)
  if math.floor(value) ~= value then
    mem.trap()
  end
  local negative = 0
  local magnitude = value
  if value < 0 then
    negative = 1
    magnitude = -value
  end
  local total = digits_of(magnitude) + negative
  local pointer = alloc(8 + total)
  mem.store(pointer, total)
  if negative == 1 then
    mem.set_byte(pointer + 8, 45)
  end
  local index = total - 1
  local rest = magnitude
  while index >= negative do
    mem.set_byte(pointer + 8 + index, 48 + (rest - math.floor(rest / 10) * 10))
    rest = math.floor(rest / 10)
    index = index - 1
  end
  return box.pack(2, pointer)
end

function concat(left, right)
  local first_value = left
  local second_value = right
  if box.is_number(first_value) then
    first_value = number_string(first_value)
  end
  if box.is_number(second_value) then
    second_value = number_string(second_value)
  end
  if box.tag(first_value) ~= 2 or box.tag(second_value) ~= 2 then
    mem.trap()
  end
  local from = box.address(first_value)
  local to = box.address(second_value)
  local first = mem.load(from)
  local second = mem.load(to)
  local pointer = alloc(8 + first + second)
  mem.store(pointer, first + second)
  local index = 0
  while index < first do
    mem.set_byte(pointer + 8 + index, mem.byte(from + 8 + index))
    index = index + 1
  end
  index = 0
  while index < second do
    mem.set_byte(pointer + 8 + first + index, mem.byte(to + 8 + index))
    index = index + 1
  end
  return box.pack(2, pointer)
end

function equal(a, b)
  if box.is_number(a) then
    if box.is_number(b) then
      if a == b then
        return 1
      end
      return 0
    end
    return 0
  end
  if box.is_number(b) then
    return 0
  end
  if box.same(a, b) then
    return 1
  end
  if box.tag(a) ~= 2 or box.tag(b) ~= 2 then
    return 0
  end
  local from = box.address(a)
  local to = box.address(b)
  local size = mem.load(from)
  if size ~= mem.load(to) then
    return 0
  end
  local index = 0
  while index < size do
    if mem.byte(from + 8 + index) ~= mem.byte(to + 8 + index) then
      return 0
    end
    index = index + 1
  end
  return 1
end

local function fold(value)
  return value - math.floor(value / 4294967296) * 4294967296
end

local function string_hash(address)
  local size = mem.load(address)
  local hash = 2166136261
  local index = 0
  while index < size do
    hash = bit.mul(bit.bxor(hash, mem.byte(address + 8 + index)), 16777619)
    index = index + 1
  end
  return bit.band(hash, 2147483647)
end

local function hash_of(key)
  if box.is_number(key) then
    return bit.band(fold(key * 2654435761 + 97), 2147483647)
  end
  if box.tag(key) == 2 then
    return string_hash(box.address(key))
  end
  return bit.band(fold(box.address(key) * 2654435761 + 97), 2147483647)
end

function table_new()
  local pointer = alloc(48)
  mem.store(pointer, 0)
  mem.store(pointer + 8, 0)
  mem.store(pointer + 16, 0)
  mem.store(pointer + 24, 0)
  mem.store(pointer + 32, 0)
  mem.store(pointer + 40, 0)
  return box.pack(3, pointer)
end

local function body_of(value)
  if box.is_number(value) then
    mem.trap()
  end
  if box.tag(value) ~= 3 then
    mem.trap()
  end
  return box.address(value)
end

local function array_grow(pointer, wanted)
  local capacity = mem.load(pointer)
  if wanted <= capacity then
    return 0
  end
  local fresh_capacity = 8
  while fresh_capacity < wanted do
    fresh_capacity = fresh_capacity * 2
  end
  local fresh = alloc(fresh_capacity * 8)
  local old = mem.load(pointer + 32)
  local count = mem.load(pointer + 8)
  local index = 0
  while index < count do
    mem.store(fresh + index * 8, mem.load(old + index * 8))
    index = index + 1
  end
  mem.store(pointer, fresh_capacity)
  mem.store(pointer + 32, fresh)
  return 0
end

local function slot_for(slots, capacity, key)
  local mask = capacity - 1
  local index = bit.band(hash_of(key), mask)
  while true do
    local slot = slots + index * 16
    local stored = mem.load(slot)
    if box.same(stored, nil) then
      return slot
    end
    if equal(stored, key) == 1 then
      return slot
    end
    index = bit.band(index + 1, mask)
  end
end

local function hash_grow(pointer)
  local capacity = mem.load(pointer + 16)
  local fresh_capacity = 8
  if capacity > 0 then
    fresh_capacity = capacity * 2
  end
  local fresh = alloc(fresh_capacity * 16)
  local index = 0
  while index < fresh_capacity do
    mem.store(fresh + index * 16, nil)
    mem.store(fresh + index * 16 + 8, nil)
    index = index + 1
  end
  local old = mem.load(pointer + 40)
  index = 0
  while index < capacity do
    local slot = old + index * 16
    local key = mem.load(slot)
    if not box.same(key, nil) then
      local target = slot_for(fresh, fresh_capacity, key)
      mem.store(target, key)
      mem.store(target + 8, mem.load(slot + 8))
    end
    index = index + 1
  end
  mem.store(pointer + 16, fresh_capacity)
  mem.store(pointer + 40, fresh)
  return 0
end

function table_set(value, key, item)
  local pointer = body_of(value)
  if box.is_number(key) then
    local index = math.floor(key)
    local count = mem.load(pointer + 8)
    if index == key and index >= 1 and index <= count + 1 then
      array_grow(pointer, index)
      mem.store(mem.load(pointer + 32) + (index - 1) * 8, item)
      if index > count then
        mem.store(pointer + 8, index)
      end
      return item
    end
  end
  if box.same(key, nil) then
    mem.trap()
  end
  local used = mem.load(pointer + 24)
  local capacity = mem.load(pointer + 16)
  if (used + 1) * 2 > capacity then
    hash_grow(pointer)
    capacity = mem.load(pointer + 16)
  end
  local slot = slot_for(mem.load(pointer + 40), capacity, key)
  if box.same(mem.load(slot), nil) then
    mem.store(pointer + 24, used + 1)
  end
  mem.store(slot, key)
  mem.store(slot + 8, item)
  return item
end

function table_get(value, key)
  local pointer = body_of(value)
  if box.is_number(key) then
    local index = math.floor(key)
    if index == key and index >= 1 and index <= mem.load(pointer + 8) then
      return mem.load(mem.load(pointer + 32) + (index - 1) * 8)
    end
  end
  local capacity = mem.load(pointer + 16)
  if capacity == 0 then
    return nil
  end
  local slot = slot_for(mem.load(pointer + 40), capacity, key)
  if box.same(mem.load(slot), nil) then
    return nil
  end
  return mem.load(slot + 8)
end
]]

return runtime
