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
  assets["/_lunar/moonlight.lua"] = integrity.hash(assert(require("lunar.site.bundle").build(app)))
  local wasm = app:wasm_manifest()
  if wasm then
    local wasm_lib = require("lunar.site.wasm")
    assets["/_lunar/wasm/index.json"] = integrity.hash(json.encode(wasm_lib.index(wasm)))
    for _, name in ipairs(wasm.order) do
      assets["/_lunar/wasm/" .. name .. ".wasm"] = integrity.hash(wasm.parts[name].bytes)
    end
  end
  return { version = 1, assets = assets }
end

return integrity
