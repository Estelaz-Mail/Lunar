--- The browser entry point, and the only file here that needs a browser.
--
-- Fengari runs this: the document shell links it as
-- `<script type="application/lua" src="/_lunar/moonlight.lua">`, and the bundle
-- that URL serves ends by calling `start`.

local moonlight = require("lunar.site.moonlight")
local dom_lib = require("lunar.runtime.dom")
local json = require("lunar.core.json")

local boot = {}

--- A plain JS object. Never `eval`: the Content Security Policy this framework
-- ships forbids it, and a framework that needs an exception to its own policy
-- has the wrong policy or the wrong code.
local function js_object(js, window, fields)
  local object = js.new(window.Object)
  for key, value in pairs(fields or {}) do object[key] = value end
  return object
end

--- `then` is a Lua keyword, so a promise is chained through indexing.
local function chain(promise, on_resolved, on_rejected)
  local next_promise = promise["then"](promise, on_resolved)
  if on_rejected then return next_promise["catch"](next_promise, on_rejected) end
  return next_promise
end

--- Starts the browser half. Outside a browser there is no `js` module, and
-- this is a no-op that says so rather than an error: the bundle is loaded by
-- `spec/bundle_spec.lua` in a plain Lua state, where everything above this
-- function is exactly what runs in a page.
function boot.start(registry)
  local has_interop, js = pcall(require, "js")
  if not has_interop then return nil, "lunar: not running in a browser" end
  local window = js.global
  local document = window.document

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
  local session = moonlight.start(registry, payload, dom, target)

  -- Client-side navigation. One delegated listener on the document rather
  -- than one per link, because the links change as the page does.
  local function navigate(path, push)
    local options = js_object(js, window, {
      headers = js_object(js, window, { Accept = "application/json" }),
      credentials = "same-origin",
    })
    chain(chain(window:fetch(path, options), function(res)
      if not res.ok then
        -- A route the client cannot render is a route the server can: let the
        -- browser do what it would have done without any of this.
        window.location.href = path
        return nil
      end
      return res:text()
    end), function(text)
      if text == nil then return end
      local next_payload = json.decode(text)
      if type(next_payload) ~= "table" then
        window.location.href = path
        return
      end
      local ok = session:swap(next_payload)
      if not ok then
        window.location.href = path
        return
      end
      if push then window.history:pushState(nil, "", path) end
      window:scrollTo(0, 0)
    end, function()
      window.location.href = path
    end)
  end

  document:addEventListener("click", function(event)
    if event.defaultPrevented or event.button ~= 0 then return end
    if event.metaKey or event.ctrlKey or event.shiftKey or event.altKey then return end

    local node = event.target
    while node and node ~= nil and node.tagName ~= "A" do node = node.parentElement end
    if not node or node == nil then return end
    if node:getAttribute("target") or node:getAttribute("download") then return end
    if node:hasAttribute("data-lunar-reload") then return end

    local href = node:getAttribute("href")
    if not href or href == nil then return end
    local url = js.new(window.URL, node.href)
    if url.origin ~= window.location.origin then return end
    -- A fragment on this page is the browser's job, not the router's.
    if url.pathname == window.location.pathname and url.hash ~= "" then return end

    event:preventDefault()
    navigate(url.pathname .. url.search, true)
  end)

  window:addEventListener("popstate", function()
    navigate(window.location.pathname .. window.location.search, false)
  end)

  window.lunar = js_object(js, window, {})
  return session
end

return boot
