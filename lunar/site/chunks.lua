local chunks = {}

local Loader = {}
Loader.__index = Loader

function chunks.loader(options)
  options = options or {}
  return setmetatable({
    fetch_text = options.fetch_text,
    warn = options.warn or function() end,
    held = {},
    pending = {},
  }, Loader)
end

function Loader:hold(url)
  if type(url) == "string" then self.held[url] = true end
  return self
end

function Loader:has(url)
  return type(url) ~= "string" or self.held[url] == true
end

function Loader:run(url, source)
  if type(source) ~= "string" then
    self.warn("lunar: " .. url .. " came back empty")
    return false
  end

  local piece, message = load(source, "@" .. url)
  if not piece then
    self.warn("lunar: " .. url .. " did not parse: " .. tostring(message))
    return false
  end

  local ran, failure = pcall(piece)
  if not ran then
    self.warn("lunar: " .. url .. " did not run: " .. tostring(failure))
    return false
  end

  self.held[url] = true
  return true
end

function Loader:ensure(url, carry_on, give_up)
  give_up = give_up or function() end
  if self:has(url) then return carry_on() end
  if not self.fetch_text then
    self.warn("lunar: nothing to fetch " .. url .. " with")
    return give_up()
  end

  local waiting = self.pending[url]
  if waiting then
    waiting[#waiting + 1] = { carry_on, give_up }
    return
  end
  waiting = { { carry_on, give_up } }
  self.pending[url] = waiting

  local function finish(success)
    if self.pending[url] ~= waiting then return end
    self.pending[url] = nil
    for _, callbacks in ipairs(waiting) do
      local ok, message = pcall(callbacks[success and 1 or 2])
      if not ok then
        self.warn("lunar: chunk callback failed: " .. tostring(message))
        if success then pcall(callbacks[2]) end
      end
    end
  end

  local ok, message = pcall(self.fetch_text, url, function(source)
    if self.pending[url] ~= waiting then return end
    finish(self:run(url, source))
  end, function() finish(false) end)
  if not ok then
    self.warn("lunar: chunk fetch failed: " .. tostring(message))
    finish(false)
  end
end

chunks.Loader = Loader

return chunks
