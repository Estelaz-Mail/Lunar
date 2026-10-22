local fs = require("lunar.core.fs")
local json = require("lunar.core.json")
local util = require("lunar.core.util")

local manifest = {}

manifest.FILE = "lunar.json"

local READ = {
  name = "string",
  version = "string",
  lang = "string",
  host = "string",
  port = "number",
  client = "boolean",
  dev = "boolean",
  minify = "boolean",
  stylesheets = "table",
  security = "table",
  rate_limit = "table",
}

local IGNORED = {
  description = true,
  author = true,
  license = true,
  repository = true,
  homepage = true,
  keywords = true,
  private = true,
}

function manifest.path(root)
  return fs.join(root or ".", manifest.FILE)
end

function manifest.read(root)
  local path = manifest.path(root)
  local source = util.read_file(path)
  if not source then return {}, nil, nil end

  local value, err = json.decode(source)
  if value == nil then return nil, string.format("lunar: %s: %s", path, tostring(err)) end
  if type(value) ~= "table" or value[1] ~= nil then
    return nil, string.format("lunar: %s: the manifest must be a JSON object", path)
  end

  local out = {}
  for key, given in pairs(value) do
    local wanted = READ[key]
    if wanted then
      if type(given) ~= wanted then
        return nil, string.format("lunar: %s: %s must be a %s, got a %s",
          path, key, wanted, type(given))
      end
      out[key] = given
    elseif not IGNORED[key] then
      return nil, string.format("lunar: %s: %s is not something Lunar reads", path, key)
    end
  end

  if out.port and (out.port < 1 or out.port > 65535 or out.port % 1 ~= 0) then
    return nil, string.format("lunar: %s: port must be a whole number between 1 and 65535", path)
  end

  if out.stylesheets then
    for index, href in ipairs(out.stylesheets) do
      if type(href) ~= "string" then
        return nil, string.format("lunar: %s: stylesheets[%d] must be a string", path, index)
      end
    end
  end

  return out, nil, path
end

manifest.READ = READ
manifest.IGNORED = IGNORED

return manifest
