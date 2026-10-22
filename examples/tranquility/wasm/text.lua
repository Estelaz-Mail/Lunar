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
