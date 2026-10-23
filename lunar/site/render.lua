local component = require("lunar.runtime.component")
local errors = require("lunar.site.errors")
local html = require("lunar.core.html")
local json = require("lunar.core.json")
local util = require("lunar.core.util")

local render = {}

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

function render.drawn(levels)
  local out = {}
  for _, level in ipairs(levels) do
    if level.component then out[#out + 1] = level end
  end
  return out
end

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

function render.document(app, parts)
  local shell = app.shell or DEFAULT_SHELL

  local head = {}
  for _, tag in ipairs(parts.head or {}) do head[#head + 1] = tag end
  if not table.concat(head):find("<title", 1, true) then
    head[#head + 1] = "<title>" .. html.escape(parts.title or app.name or "Lunar") .. "</title>"
  end

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
    body[#body + 1] = string.format(
      '<script type="application/json" id="lunar-data">%s</script>',
      json.encode(parts.data))
  end

  if app.client ~= false then
    local integrity = app:client_integrity()
    body[#body + 1] = string.format('<script type="application/json" id="lunar-integrity">%s</script>',
      json.encode(integrity))
    body[#body + 1] = string.format('<script type="module" src="%s" integrity="%s" crossorigin="anonymous"></script>',
      html.escape("/_lunar/runtime/boot?v=" .. app.version),
      html.escape(assert(integrity.assets["/_lunar/runtime/boot"])))
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
