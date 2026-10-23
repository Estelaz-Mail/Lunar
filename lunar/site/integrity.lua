local base64 = require("lunar.core.base64")
local sha256 = require("lunar.crypto.sha256")
local fs = require("lunar.core.fs")
local json = require("lunar.core.json")

local integrity = {}

function integrity.hash(source)
  return "sha256-" .. base64.encode(sha256.digest(source))
end

function integrity.source(app, name)
  local path = fs.join(app.framework, "static/runtime", name)
  if name == "boot" or name == "bridge" then
    local artifact = assert(json.decode(assert(fs.read(path .. ".json"))), "lunar: invalid runtime artifact")
    assert(type(artifact.source) == "string", "lunar: missing runtime source")
    return artifact.source
  end
  return assert(fs.read(path), "lunar: missing runtime asset " .. name)
end

function integrity.build(app)
  local assets = {}
  for _, name in ipairs({ "boot", "bridge", "lua54.wasm" }) do
    local source = integrity.source(app, name)
    assets["/_lunar/runtime/" .. name] = integrity.hash(source)
  end
  local bundle_lib = require("lunar.site.bundle")
  assets["/_lunar/moonlight.lua"] = integrity.hash(assert(bundle_lib.build(app)))
  for _, chunk in pairs(bundle_lib.chunks(app) or {}) do
    assets[bundle_lib.CHUNKS .. chunk.name] = integrity.hash(chunk.source)
  end
  local wasm = app:wasm_manifest()
  if wasm then
    local wasm_lib = require("lunar.site.wasm")
    assets["/_lunar/wasm/index.json"] = integrity.hash(json.encode(wasm_lib.index(wasm)))
    for _, name in ipairs(wasm.order) do
      assets["/_lunar/wasm/" .. name .. ".wasm"] = integrity.hash(wasm.parts[name].bytes)
    end
  end
  return { version = 1, assets = assets,
    revision = sha256.hex(sha256.digest(json.encode(assets))) }
end

return integrity
