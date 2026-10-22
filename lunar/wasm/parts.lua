local compile = require("lunar.wasm.compile")
local parse = require("lunar.wasm.parse")
local runtime_lib = require("lunar.wasm.runtime")
local util = require("lunar.core.util")

local parts = {}

local function aligned(size)
  return size + ((8 - (size % 8)) % 8)
end

function parts.build(units, options)
  options = options or {}
  local manifest = { parts = {}, index = {}, order = {} }
  local externals = {}

  local declared = {}
  for _, unit in ipairs(units) do
    if unit.name == runtime_lib.NAME then
      error("lunar: `" .. runtime_lib.NAME .. "` is the name of Lunar's own wasm part", 0)
    end
  end
  for _, unit in ipairs(units) do
    for _, declaration in ipairs(parse.chunk(unit.source,
      { filename = unit.filename or ((unit.name or "part") .. ".lua") })) do
      if declaration.exported then
        declared[declaration.name] = { arity = #declaration.parameters, part = unit.name }
      end
    end
  end

  local bases, cursor = {}, runtime_lib.DATA_START
  for _, unit in ipairs(units) do
    local _, measured = compile.chunk(unit.source, {
      filename = unit.filename or ((unit.name or "part") .. ".lua"),
      externals = declared,
    })
    bases[unit.name] = cursor
    cursor = cursor + aligned(measured.data_size)
  end

  for _, unit in ipairs(units) do
    local name = unit.name or error("lunar: a wasm part needs a name", 0)
    if manifest.parts[name] then
      error("lunar: there are two wasm parts called " .. name, 0)
    end

    local bytes, info = compile.chunk(unit.source, {
      filename = unit.filename or (name .. ".lua"),
      externals = externals,
      data_base = bases[name],
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

  local wanted = false
  for _, name in ipairs(manifest.order) do
    for _, needed in ipairs(manifest.parts[name].needs) do
      if needed == runtime_lib.NAME then wanted = true end
    end
  end

  if wanted then
    local bytes, info = compile.chunk(runtime_lib.SOURCE, {
      filename = "runtime.lua",
      is_runtime = true,
      memory = true,
      data_segments = { { offset = 0, bytes = string.pack("<d", cursor) } },
    })
    manifest.parts[runtime_lib.NAME] = {
      name = runtime_lib.NAME,
      bytes = bytes,
      exports = info.exports,
      arities = info.arities,
      needs = {},
      host = info.host,
      digest = util.hash(bytes),
      internal = true,
    }
    table.insert(manifest.order, 1, runtime_lib.NAME)
  end

  manifest.heap = cursor
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
