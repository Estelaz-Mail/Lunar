local compile = require("lunar.wasm.compile")
local util = require("lunar.core.util")

local parts = {}

function parts.build(units, options)
  options = options or {}
  local manifest = { parts = {}, index = {}, order = {} }
  local externals = {}

  for _, unit in ipairs(units) do
    local name = unit.name or error("lunar: a wasm part needs a name", 0)
    if manifest.parts[name] then
      error("lunar: there are two wasm parts called " .. name, 0)
    end

    local bytes, info = compile.chunk(unit.source, {
      filename = unit.filename or (name .. ".lua"),
      externals = externals,
    })

    manifest.parts[name] = {
      name = name,
      bytes = bytes,
      exports = info.exports,
      arities = info.arities,
      needs = info.needs,
      host = info.host,
      digest = util.hash(bytes),
    }
    manifest.order[#manifest.order + 1] = name

    for _, exported in ipairs(info.exports) do
      if manifest.index[exported] then
        error(string.format("lunar: `%s` is exported by both %s and %s", exported,
          manifest.index[exported], name), 0)
      end
      manifest.index[exported] = name
      externals[exported] = { arity = info.arities[exported], part = name, name = exported }
    end
  end

  return manifest
end

function parts.resolve(manifest, name)
  local part = manifest.parts[manifest.index[name] or ""]
  if not part then return nil end
  return part
end

function parts.chain(manifest, name)
  local wanted = manifest.index[name]
  if not wanted then return nil end
  local ordered, seen = {}, {}
  local function visit(part_name)
    if seen[part_name] then return end
    seen[part_name] = true
    local part = manifest.parts[part_name]
    if not part then error("lunar: the wasm part " .. part_name .. " is missing", 0) end
    for _, dependency in ipairs(part.needs) do visit(dependency) end
    ordered[#ordered + 1] = part_name
  end
  visit(wanted)
  return ordered
end

return parts
