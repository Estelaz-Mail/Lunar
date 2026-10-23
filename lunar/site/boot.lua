local chunks_lib = require("lunar.site.chunks")
local moonlight = require("lunar.site.moonlight")
local dom_lib = require("lunar.runtime.dom")
local wasm_lib = require("lunar.runtime.wasm")
local json = require("lunar.core.json")

local boot = {}

local function js_object(js, window, fields)
  local object = js.new(window.Object)
  for key, value in pairs(fields or {}) do object[key] = value end
  return object
end

local function chain(promise, on_resolved, on_rejected)
  local next_promise = promise["then"](promise, on_resolved)
  if on_rejected then return next_promise["catch"](next_promise, on_rejected) end
  return next_promise
end

function boot.start(registry)
  local has_interop, js = pcall(require, "js")
  if not has_interop then return nil, "lunar: not running in a browser" end
  local window = js.global
  local document = window.document
  local function present(value)
    if value == js.null then return nil end
    return value
  end

  local target = document:getElementById("lunar")
  if not target then
    window.console:warn("lunar: no #lunar element to mount into")
    return
  end

  local block = document:getElementById("lunar-data")
  if not block then
    window.console:warn("lunar: the page carries no data block")
    return
  end

  local payload = json.decode(block.textContent)
  if type(payload) ~= "table" then
    window.console:warn("lunar: the page's data block is not JSON")
    return
  end

  local dom = dom_lib.browser(window, js)
  local loader = window.WebAssembly and wasm_lib.browser(window, js) or nil
  local session = moonlight.start(registry, payload, dom, target, {
    wasm = loader,
    on_rebuild = function(reason)
      window.console:warn("lunar: the page was rebuilt rather than claimed: " .. tostring(reason))
    end,
  })

  local current_page = window.location.pathname .. window.location.search

  local pieces = chunks_lib.loader({
    warn = function(message) window.console:warn(message) end,
    fetch_text = function(url, on_text, on_error)
      local verified = window.lunarFetchVerified
      if not verified then return on_error() end
      chain(chain(verified(url), function(res) return res:text() end), on_text, on_error)
    end,
  })
  pieces:hold(payload.chunk)

  local function scroll_to_url(url)
    if url.hash ~= "" then
      local ok, id = pcall(function() return window:decodeURIComponent(url.hash:sub(2)) end)
      local anchor = present(document:getElementById(ok and id or url.hash:sub(2)))
      if anchor then
        anchor:scrollIntoView()
        return
      end
    end
    window:scrollTo(0, 0)
  end

  local function navigate(path, push)
    local destination = js.new(window.URL, path, window.location.href)
    local generation = session:begin_navigation(path)

    local function give_up()
      if not session:is_current(generation) then return end
      window.location.href = path
    end

    local options = js_object(js, window, {
      headers = js_object(js, window, { Accept = "application/json" }),
      credentials = "same-origin",
    })

    chain(chain(window:fetch(path, options), function(res)
      if not session:is_current(generation) then return nil end
      if not res.ok then
        give_up()
        return nil
      end
      return res:text()
    end), function(text)
      if text == nil then return end
      if not session:is_current(generation) then return end

      local next_payload = json.decode(text)
      if type(next_payload) ~= "table" then
        give_up()
        return
      end

      pieces:ensure(next_payload.chunk, function()
        if not session:is_current(generation) then return end
        local ok = session:apply(generation, next_payload)
        if not ok then
          give_up()
          return
        end
        if push then window.history:pushState(nil, "", path) end
        current_page = destination.pathname .. destination.search
        scroll_to_url(destination)
      end, give_up)
    end, give_up)
  end

  document:addEventListener("click", function(event)
    if event.defaultPrevented or event.button ~= 0 then return end
    if event.metaKey or event.ctrlKey or event.shiftKey or event.altKey then return end

    local node = present(event.target)
    while node and node.tagName ~= "A" do node = present(node.parentElement) end
    if not node then return end
    if present(node:getAttribute("target")) or present(node:getAttribute("download")) then return end
    if node:hasAttribute("data-lunar-reload") then return end

    local href = present(node:getAttribute("href"))
    if not href then return end
    local url = js.new(window.URL, node.href)
    if url.origin ~= window.location.origin then return end
    if url.pathname .. url.search == current_page and url.hash ~= "" then return end

    event:preventDefault()
    navigate(url.pathname .. url.search .. url.hash, true)
  end)

  window:addEventListener("popstate", function()
    local page = window.location.pathname .. window.location.search
    if page == current_page then return end
    navigate(page .. window.location.hash, false)
  end)

  window.lunar = js_object(js, window, {})
  return session
end

return boot
