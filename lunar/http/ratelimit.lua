--- Per-address rate limiting.
--
-- A token bucket per client address, in three classes, because one limit
-- cannot fit both a page view and the subresources it pulls: opening a page is
-- one HTML request and twenty files, and a form endpoint should allow neither
-- twenty nor a hundred.
--
--   page    the rendered pages and the route data the client router fetches
--   asset   anything that came off disk: CSS, fonts, images, the client Lua
--   write   every non-GET request
--
-- The state is this process's, so two instances behind a proxy each allow
-- their own budget. That is the right trade for what this protects against — a
-- scraper walking every page, a loop hammering a form — and a shared limiter
-- would mean a dependency, which this framework does not have.
--
-- Nothing here identifies a visitor: the key is the address, the entry holds
-- two numbers, and it is dropped as soon as the bucket is full again.

local util = require("lunar.core.util")

local ratelimit = {}

local Limiter = {}
Limiter.__index = Limiter

local DEFAULT_CLASSES = {
  page = { capacity = 60, per_second = 2 },
  asset = { capacity = 300, per_second = 20 },
  write = { capacity = 20, per_second = 0.5 },
}

local ASSET_PREFIXES = { "/_lunar/", "/static/", "/css/", "/fonts/", "/images/",
  "/videos/", "/assets/" }
local ASSET_EXTENSIONS = {
  avif = true, css = true, gif = true, ico = true, jpeg = true, jpg = true,
  js = true, lua = true, m4a = true, map = true, mjs = true, mp3 = true,
  mp4 = true, otf = true, png = true, svg = true, ttf = true, wasm = true,
  webm = true, webp = true, woff = true, woff2 = true,
}

--- Which bucket a request draws from, from its method and the shape of its
-- path. The static handler has not run yet, so whether the file exists is not
-- knowable here — and a request for a file that is missing is cheap either way.
function ratelimit.classify(req)
  if req.method ~= "GET" and req.method ~= "HEAD" then return "write" end
  local path = req.path or "/"
  for _, prefix in ipairs(ASSET_PREFIXES) do
    if util.starts_with(path, prefix) then return "asset" end
  end
  local extension = path:match("%.([%w]+)$")
  if extension and ASSET_EXTENSIONS[extension:lower()] then return "asset" end
  return "page"
end

local function default_clock()
  local ok, socket = pcall(require, "socket")
  if ok and socket.gettime then return socket.gettime end
  return function() return os.time() end
end

--- `options` is `{ classes, max_keys, idle_seconds, exempt, now, enabled }`.
function ratelimit.new(options)
  options = options or {}
  local classes = {}
  for name, config in pairs(options.classes or DEFAULT_CLASSES) do
    classes[name] = {
      capacity = math.max(1, tonumber(config.capacity) or 1),
      per_second = math.max(0.0001, tonumber(config.per_second) or 1),
    }
  end

  local exempt = {}
  for _, address in ipairs(options.exempt or {}) do exempt[address] = true end

  return setmetatable({
    enabled = options.enabled ~= false,
    classes = classes,
    -- The ceiling on how many addresses are remembered. Past it the idle
    -- entries go first and the oldest after that, so a flood from a wide
    -- range of addresses costs a bounded amount of memory and not an
    -- unbounded one.
    max_keys = math.max(16, math.floor(tonumber(options.max_keys) or 8192)),
    idle_seconds = tonumber(options.idle_seconds) or 600,
    exempt = exempt,
    now = options.now or default_clock(),
    entries = {},
    count = 0,
  }, Limiter)
end

function Limiter:prune(now)
  local survivors = {}
  for key, entry in pairs(self.entries) do
    local idle = (now - entry.seen) > self.idle_seconds
    local full = true
    for class, bucket in pairs(entry.buckets) do
      if bucket.tokens < self.classes[class].capacity then full = false end
    end
    if idle or full then
      self.entries[key] = nil
      self.count = self.count - 1
    else
      survivors[#survivors + 1] = { key = key, seen = entry.seen }
    end
  end

  if self.count <= self.max_keys then return end
  table.sort(survivors, function(a, b) return a.seen < b.seen end)
  for index = 1, self.count - self.max_keys do
    local victim = survivors[index]
    if not victim then break end
    self.entries[victim.key] = nil
    self.count = self.count - 1
  end
end

local function bucket_for(self, key, class, now)
  local entry = self.entries[key]
  if not entry then
    if self.count >= self.max_keys then self:prune(now) end
    entry = { buckets = {}, seen = now }
    self.entries[key] = entry
    self.count = self.count + 1
  end
  entry.seen = now

  local bucket = entry.buckets[class]
  if not bucket then
    bucket = { tokens = self.classes[class].capacity, updated = now }
    entry.buckets[class] = bucket
  end
  return bucket
end

--- Takes one token. Returns true when the request may proceed, or false and
-- the whole seconds until the next token, which is what `Retry-After` wants.
function Limiter:take(key, class, cost)
  if not self.enabled then return true end
  if key == nil or key == "" or self.exempt[key] then return true end
  class = self.classes[class] and class or "page"
  local config = self.classes[class]
  if not config then return true end
  cost = cost or 1

  local now = self.now()
  local bucket = bucket_for(self, key, class, now)

  bucket.tokens = math.min(config.capacity,
    bucket.tokens + math.max(0, now - bucket.updated) * config.per_second)
  bucket.updated = now

  if bucket.tokens >= cost then
    bucket.tokens = bucket.tokens - cost
    return true
  end
  return false, math.max(1, math.ceil((cost - bucket.tokens) / config.per_second))
end

--- The middleware. It answers only when the request is over its budget, so it
-- sits at the front of the route table like any other.
function Limiter:middleware()
  local response = require("lunar.http.response")
  return function(req)
    local class = ratelimit.classify(req)
    local ok, retry_after = self:take(req.ip, class)
    if ok then return nil end

    local res = response.text("429 Too Many Requests\nSlow down.\n", 429, {
      ["Retry-After"] = tostring(retry_after),
      ["Cache-Control"] = "no-store",
    })
    -- The connection goes with the response: a client that is over its budget
    -- should not also hold a slot in the event loop.
    res.close = true
    return res
  end
end

ratelimit.Limiter = Limiter
ratelimit.DEFAULT_CLASSES = DEFAULT_CLASSES

return ratelimit
