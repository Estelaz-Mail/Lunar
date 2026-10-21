--- Resolving one component's path from inside another.
--
-- `import("./Card.lunar")` has to mean the same file on the server, where it
-- is read from disk, and in the browser, where it is a key in the bundle's
-- registry. So the path arithmetic lives here and both use it.
--
-- It is textual: there is no `realpath` without a C module, and a component
-- path is written by the author, never taken from a request.

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

--- The module name a component is registered under in a bundle. Derived from
-- the path, so the registry needs no second lookup table.
function resolve.module_name(path)
  return "lunar.app:" .. path
end

--- An `import()` that looks in a bundle instead of on a disk.
--
-- Both bundles use this: the browser's, where there is no filesystem, and the
-- server's, when the app is frozen for a platform that has none either. The
-- registry is `{ root, components = { [path] = module name } }`.
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
