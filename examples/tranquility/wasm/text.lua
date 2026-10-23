function label(count)
  if count == 1 then
    return "one ring"
  end
  return count .. " rings"
end

function tally(count)
  local seen = {}
  local index = 1
  while index <= count do
    seen["ring" .. index] = area(index)
    index = index + 1
  end
  return seen["ring" .. count]
end

local function gather(...)
  local values = {...}
  local total = 0
  local index = 1
  while index <= #values do
    total = total + values[index]
    index = index + 1
  end
  return total, total / #values
end

function summary()
  local total, mean = gather(1, 2, 3, 4)
  return "sum " .. total .. ", mean " .. mean
end
