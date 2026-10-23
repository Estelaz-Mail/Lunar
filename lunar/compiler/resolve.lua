local resolve = {}

function resolve.normalize(path)
  if path == nil or path == "" then return "" end

  local absolute = path:sub(1, 1) == "/"
  local out = {}
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then
      local last = out[#out]
      if last ~= nil and last ~= ".." then
        out[#out] = nil
      elseif not absolute then
        out[#out + 1] = ".."
      end
    elseif segment ~= "." then
      out[#out + 1] = segment
    end
  end

  local joined = table.concat(out, "/")
  if absolute then return "/" .. joined end
  if joined == "" then return "." end
  return joined
end

function resolve.path(request, from, root)
  local path = request

  if request:sub(1, 1) == "/" then
    local base = root
    if not base or base == "" then base = "." end
    path = base:gsub("/+$", "") .. request
  elseif request:sub(1, 2) == "./" or request:sub(1, 3) == "../" then
    local directory = (from or ""):match("^(.*)/[^/]*$") or "."
    path = directory .. "/" .. request
  end

  path = resolve.normalize(path)
  if not path:match("%.lunar$") then path = path .. ".lunar" end
  return path
end

function resolve.module_name(path)
  return "lunar.app:" .. resolve.normalize(path)
end

function resolve.registry_resolver(registry)
  return function(request, from)
    local path = resolve.path(request, from, registry.root or "")
    local components = registry.components or {}
    local name = components[path] or components[resolve.normalize(path)]
    if not name then return nil, path .. " is not in the bundle" end
    local ok, def = pcall(require, name)
    if not ok then return nil, tostring(def) end
    return def
  end
end

return resolve
