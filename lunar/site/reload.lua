local json = require("lunar.core.json")

local reload = {}

local function chain(promise, on_resolved, on_rejected)
  local next_promise = promise["then"](promise, on_resolved)
  if on_rejected then return next_promise["catch"](next_promise, on_rejected) end
  return next_promise
end

function reload.watch(options)
  local has_interop, js = pcall(require, "js")
  if not has_interop then return nil, "lunar: not running in a browser" end

  local window = js.global
  local interval = (options and options.interval) or 800
  local generation = nil
  local session = nil

  local function poll()
    chain(chain(window:fetch("/_lunar/dev"), function(res)
      if not res.ok then return nil end
      return res:text()
    end), function(text)
      if text == nil then return end
      local payload = json.decode(text)
      if type(payload) ~= "table" or payload.generation == nil then return end
      if generation == nil then
        generation = payload.generation
        session = payload.session
        return
      end
      if payload.generation ~= generation or payload.session ~= session then
        generation = payload.generation
        session = payload.session
        window.location:reload()
      end
    end, function() end)
  end

  window:setInterval(poll, interval)
  return true
end

return reload
