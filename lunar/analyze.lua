local bundle = require("lunar.site.bundle")
local gzip = require("lunar.core.gzip")
local integrity = require("lunar.site.integrity")
local json = require("lunar.core.json")

local analyze = {}

local function packed(source)
  return #gzip.compress(source)
end

local function resource(name, path, source)
  return { name = name, path = path, bytes = #source, gzip = packed(source) }
end

function analyze.run(root, options)
  options = options or {}
  local lunar = require("lunar")
  local app = lunar.app({ root = root, dev = false, version = "analyze" })

  local inventory, source = bundle.inventory(app)
  if not inventory then return nil, source end

  local downloads = {}
  if app.client ~= false then
    for _, name in ipairs({ "boot", "bridge", "lua54.wasm" }) do
      downloads[#downloads + 1] = resource(name, "/_lunar/runtime/" .. name,
        integrity.source(app, name))
    end
    downloads[#downloads + 1] = resource("moonlight", "/_lunar/moonlight.lua", source)

    local wasm = app:wasm_manifest()
    if wasm then
      local wasm_lib = require("lunar.site.wasm")
      downloads[#downloads + 1] = resource("wasm index", "/_lunar/wasm/index.json",
        json.encode(wasm_lib.index(wasm)))
      for _, name in ipairs(wasm.order) do
        downloads[#downloads + 1] = resource(name, "/_lunar/wasm/" .. name .. ".wasm",
          wasm.parts[name].bytes)
      end
    end
  end

  local prefix = app.root ~= "" and (app.root .. "/") or nil
  local parts = {}
  for _, item in ipairs(inventory) do
    local name = item.name
    if prefix and name:sub(1, #prefix) == prefix then name = name:sub(#prefix + 1) end
    parts[#parts + 1] = { kind = item.kind, name = name, bytes = item.bytes,
      gzip = packed(item.piece) }
  end
  table.sort(parts, function(a, b)
    if a.bytes == b.bytes then return a.name < b.name end
    return a.bytes > b.bytes
  end)

  local totals = { bytes = 0, gzip = 0, eager = 0 }
  for _, item in ipairs(downloads) do
    totals.bytes = totals.bytes + item.bytes
    totals.gzip = totals.gzip + item.gzip
  end

  return {
    app = app,
    downloads = downloads,
    parts = parts,
    moonlight = { bytes = #source, gzip = packed(source) },
    totals = totals,
    routes = #app.routes,
  }
end

local function kilobytes(value)
  return string.format("%8.1f KB", value / 1024)
end

local function trimmed(value)
  return (kilobytes(value):gsub("^%s+", ""))
end

local function fits(name, width)
  if #name <= width then return name end
  return "..." .. name:sub(#name - width + 4)
end

function analyze.report(result, write)
  write = write or io.write
  local lunar = require("lunar")

  write(string.format("lunar %s — %s, %d routes\n\n", lunar.VERSION,
    result.app.name or "an app", result.routes))

  write("  what the browser downloads\n\n")
  write(string.format("  %-26s %12s %12s\n", "", "raw", "gzip"))
  for _, item in ipairs(result.downloads) do
    write(string.format("  %-26s %12s %12s\n", item.name,
      kilobytes(item.bytes), kilobytes(item.gzip)))
  end
  write(string.format("  %-26s %12s %12s\n\n", "all of it",
    kilobytes(result.totals.bytes), kilobytes(result.totals.gzip)))

  write(string.format("  inside moonlight (%s raw, %s gzip)\n\n",
    (kilobytes(result.moonlight.bytes):gsub("^%s+", "")),
    (kilobytes(result.moonlight.gzip):gsub("^%s+", ""))))

  write(string.format("  %-40s %10s %7s %12s\n\n", "", "raw", "share", "gzip alone"))
  local rest = 0
  for index, item in ipairs(result.parts) do
    if index <= 20 then
      write(string.format("  %-40s %10s %6.1f%% %12s\n", fits(item.name, 40),
        trimmed(item.bytes), item.bytes / result.moonlight.bytes * 100,
        trimmed(item.gzip)))
    else
      rest = rest + 1
    end
  end
  if rest > 0 then
    write(string.format("  %d more, smaller\n", rest))
  end
  write(string.format("\n  share is of the raw bundle. gzip alone is each part compressed\n"
    .. "  by itself, and those add up to more than the %s the bundle costs,\n"
    .. "  because one stream compresses across all of them.\n\n",
    trimmed(result.moonlight.gzip)))
end

return analyze
