local resolve = {}

function resolve.path(request, from, root)
  local path = request

  if request:sub(1, 1) == "/" then
    path = (root or ""):gsub("/+$", "") .. request
  elseif request:sub(1, 2) == "./" or request:sub(1, 3) == "../" then
    local directory = (from or ""):match("^(.*)/[^/]*$") or "."
    path = directory .. "/" .. request
  end

  path = path:gsub("/%./", "/"):gsub("^%./", "")
  while true do
    local collapsed, count = path:gsub("[^/]+/%.%./", "", 1)
    path = collapsed
    if count == 0 then break end
  end

  if not path:match("%.lunar$") then path = path .. ".lunar" end
  return path
end

function resolve.module_name(path)
  return "lunar.app:" .. path
end

function resolve.registry_resolver(registry)
  return function(request, from)
    local path = resolve.path(request, from, registry.root or "")
    local name = (registry.components or {})[path]
    if not name then return nil, path .. " is not in the bundle" end
    local ok, def = pcall(require, name)
    if not ok then return nil, tostring(def) end
    return def
  end
end

return resolve
