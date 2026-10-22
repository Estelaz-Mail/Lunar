local function term(index)
  return 1 / (index * index)
end

function basel(count)
  local total = 0
  for index = 1, count do
    total = total + term(index)
  end
  return total
end

function rings(count, radius)
  local total = 0
  for index = 1, count do
    total = total + area(radius * index)
  end
  return total
end
