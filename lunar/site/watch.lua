local fs = require("lunar.core.fs")
local util = require("lunar.core.util")

local watch = {}

local WATCHED = {
  lunar = true, lua = true, html = true, css = true, js = true, json = true,
  ts = true, svg = true, wasm = true, png = true, jpg = true, jpeg = true,
  webp = true, ico = true, woff = true, woff2 = true,
}

local function clock()
  local ok, socket = pcall(require, "socket")
  if ok and socket.gettime then return socket.gettime end
  return function() return os.time() end
end

local now = clock()

local Watcher = {}
Watcher.__index = Watcher

function watch.new(options)
  options = options or {}
  return setmetatable({
    root = options.root or ".",
    interval = options.interval or 0.4,
    sources = nil,
    generation = 0,
    checked = 0,
  }, Watcher)
end

local function watched(relative)
  if relative:find("^%.") or relative:find("/%.") then return false end
  if relative:find("^node_modules/") or relative:find("/node_modules/") then return false end
  local extension = relative:match("%.([%w]+)$")
  return extension ~= nil and WATCHED[extension] == true
end

function Watcher:snapshot()
  local out = {}
  for _, relative in ipairs(fs.files(self.root)) do
    if watched(relative) then
      out[relative] = util.read_file(fs.join(self.root, relative)) or ""
    end
  end
  return out
end

function Watcher:changed(options)
  local force = options and options.force
  local moment = now()
  if not force and self.sources and moment - self.checked < self.interval then
    return false
  end
  self.checked = moment

  local fresh = self:snapshot()
  if not self.sources then
    self.sources = fresh
    self.generation = 1
    return false
  end

  local changed = false
  for relative, source in pairs(fresh) do
    if self.sources[relative] ~= source then
      changed = true
      break
    end
  end
  if not changed then
    for relative in pairs(self.sources) do
      if fresh[relative] == nil then
        changed = true
        break
      end
    end
  end

  self.sources = fresh
  if changed then self.generation = self.generation + 1 end
  return changed
end

watch.Watcher = Watcher
watch.WATCHED = WATCHED

return watch
