local fs = require("lunar.core.fs")
local parts_lib = require("lunar.wasm.parts")
local response = require("lunar.http.response")
local util = require("lunar.core.util")

local wasm = {}

wasm.DIRECTORY = "wasm"
wasm.PREFIX = "/_lunar/wasm/"

function wasm.units(root)
  local directory = fs.join(root, wasm.DIRECTORY)
  local units = {}
  for _, relative in ipairs(fs.files(directory)) do
    if relative:match("%.lua$") and not relative:find("/") then
      local path = fs.join(directory, relative)
      local source = fs.read(path)
      if source then
        units[#units + 1] = {
          name = (relative:gsub("%.lua$", "")),
          source = source,
          filename = path,
        }
      end
    end
  end
  return units
end

function wasm.build(root)
  local units = wasm.units(root)
  if #units == 0 then return nil end
  local ok, manifest = pcall(parts_lib.build, units)
  if not ok then return nil, tostring(manifest) end
  manifest.digest = util.hash(table.concat((function()
    local pieces = {}
    for _, name in ipairs(manifest.order) do
      pieces[#pieces + 1] = name .. ":" .. manifest.parts[name].digest
    end
    return pieces
  end)(), ";"))
  return manifest
end

function wasm.index(manifest)
  local parts = {}
  for _, name in ipairs(manifest.order) do
    local part = manifest.parts[name]
    parts[name] = {
      digest = part.digest,
      needs = part.needs,
      exports = part.exports,
      host = part.host,
    }
  end
  return {
    version = manifest.digest,
    index = manifest.index,
    parts = parts,
    table_size = manifest.table_size or 0,
    heap = manifest.heap or 0,
  }
end

function wasm.respond(manifest, path, immutable)
  if not manifest then return nil end
  if path == wasm.PREFIX .. "index.json" then
    return response.json(wasm.index(manifest), 200, {
      ["Cache-Control"] = immutable and "public, max-age=31536000, immutable" or "no-store",
    })
  end
  local name = path:match("^" .. util.pattern_escape(wasm.PREFIX) .. "([%w_%-]+)%.wasm$")
  local part = name and manifest.parts[name]
  if not part then return nil end
  return response.new(200, part.bytes, {
    ["Content-Type"] = "application/wasm",
    ["ETag"] = string.format('"%s"', part.digest),
    ["Cache-Control"] = immutable and "public, max-age=31536000, immutable" or "no-store",
  })
end

return wasm
