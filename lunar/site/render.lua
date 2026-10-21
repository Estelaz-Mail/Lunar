--- The render pipeline: loads, then components, then the document.
--
-- A page is the innermost component of a chain. Each shell above it renders
-- the one below it into its `<slot />`, which is the same mechanism any
-- component's children use — a shell is not a special kind of component, it is
-- a component the orbit knows where to find.

local component = require("lunar.runtime.component")
local errors = require("lunar.site.errors")
local html = require("lunar.core.html")
local json = require("lunar.core.json")
local util = require("lunar.core.util")

local render = {}

--- The event a probe, and an endpoint, receives.
function render.event(req, route, params, extra)
  local event = {
    params = params or {},
    route = route and route.id or nil,
    url = { path = req.path, search = req.search, query = req.query, host = req.host,
      origin = req.origin, scheme = req.scheme },
    request = req,
    locals = req.locals,
    fail = errors.fail,
    redirect = errors.redirect,
  }
  for key, value in pairs(extra or {}) do event[key] = value end
  return event
end

--- Runs the probes of a route, outermost first.
--
-- A probe is what a page sends ahead of itself: it runs on the server, before
-- anything is drawn, and what it brings back is the page's `data`.
--
-- Each level sees the data of the levels above it merged into its own, which
-- is what makes a shell's data available to the page inside it without the
-- page asking for it. A level that draws nothing still contributes its data.
function render.probe_chain(app, route, event)
  local levels = {}
  local cumulative = {}

  for _, level in ipairs(route.levels) do
    if level.probe then
      local module, err = app:module(level.probe)
      if not module then error(err, 0) end
      local probe = module.probe
      if probe ~= nil and type(probe) ~= "function" then
        error(string.format("lunar: %s: `probe` must be a function, got a %s",
          level.probe, type(probe)), 0)
      end
      if probe then
        local value = probe(event)
        if value ~= nil and type(value) ~= "table" then
          error(string.format("lunar: %s: a probe must return a table, got a %s",
            level.probe, type(value)), 0)
        end
        cumulative = util.merge(cumulative, value)
      end
    end
    levels[#levels + 1] = { data = util.merge(cumulative), component = level.component }
  end

  return levels
end

--- The levels that draw something, with their data: what both renderers walk.
function render.drawn(levels)
  local out = {}
  for _, level in ipairs(levels) do
    if level.component then out[#out + 1] = level end
  end
  return out
end

--- Renders the chain to markup. `defs` is outermost first; `data` is the
-- data for each of them, already merged down the chain.
function render.chain(defs, data, options)
  local ctx = component.context((options and options.ctx) or nil)
  local params = (options and options.params) or {}

  local function at(index)
    local props = { data = data[index] or {}, params = params }
    if index == #defs then
      return component.render(defs[index], props, { ctx = ctx })
    end
    local inner = at(index + 1)
    return component.render(defs[index], props, {
      ctx = ctx,
      -- The shell's `<slot />`: the markup of everything below it.
      slot = function(out) out[#out + 1] = inner end,
    })
  end

  if #defs == 0 then return "", ctx end
  return at(1), ctx
end

local DEFAULT_SHELL = [[<!doctype html>
<html lang="%lunar.lang%">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
%lunar.head%
</head>
<body>
%lunar.body%
</body>
</html>
]]

--- The document. `app.html` in the app's root replaces the default shell; the
-- two placeholders are all it has to carry.
function render.document(app, parts)
  local shell = app.shell or DEFAULT_SHELL

  local head = {}
  for _, tag in ipairs(parts.head or {}) do head[#head + 1] = tag end
  if not table.concat(head):find("<title", 1, true) then
    head[#head + 1] = "<title>" .. html.escape(parts.title or app.name or "Lunar") .. "</title>"
  end

  -- The styles of the components this page actually rendered, in a stable
  -- order so the same page is the same bytes.
  local sheets = {}
  for _, class in ipairs(util.keys(parts.css or {})) do
    sheets[#sheets + 1] = parts.css[class]
  end
  if #sheets > 0 then
    head[#head + 1] = "<style>" .. table.concat(sheets, "\n") .. "</style>"
  end
  for _, href in ipairs(app.stylesheets or {}) do
    head[#head + 1] = string.format('<link rel="stylesheet" href="%s">', html.escape(href))
  end

  local body = { string.format('<div id="lunar">%s</div>', parts.body or "") }

  if parts.data then
    -- A data block, not a script: `type="application/json"` is not executed,
    -- so it needs no exception in the Content Security Policy. The JSON
    -- encoder escapes `<` and `>`, so a string in the data cannot end the
    -- element it sits in.
    body[#body + 1] = string.format(
      '<script type="application/json" id="lunar-data">%s</script>',
      json.encode(parts.data))
  end

  if app.client ~= false then
    body[#body + 1] = string.format('<script src="%s" defer></script>',
      html.escape("/_lunar/fengari.js?v=" .. app.version))
    -- The moonlight: the app again, for the browser.
    body[#body + 1] = string.format('<script type="application/lua" src="%s" async></script>',
      html.escape("/_lunar/moonlight.lua?v=" .. app.version))
  end

  local replacements = {
    ["%lunar.lang%"] = html.escape(app.lang or "en"),
    ["%lunar.head%"] = table.concat(head, "\n"),
    ["%lunar.body%"] = table.concat(body, "\n"),
  }

  return (shell:gsub("%%lunar%.%w+%%", function(key)
    return replacements[key] or ""
  end))
end

render.DEFAULT_SHELL = DEFAULT_SHELL

return render
