local chunks = {}

local Loader = {}
Loader.__index = Loader

function chunks.loader(options)
  options = options or {}
  return setmetatable({
    fetch_text = options.fetch_text,
    warn = options.warn or function() end,
    held = {},
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

  self.fetch_text(url, function(source)
    if not self:run(url, source) then return give_up() end
    carry_on()
  end, give_up)
end

chunks.Loader = Loader

return chunks
