--- A route table, for the endpoints an app adds next to its pages.
--
-- The filesystem routes are `kit.routes`; this is the plain router underneath,
-- and the one an app uses directly when it wants a URL that is not a page.
-- `:name` is one segment, `*name` is the rest of the path, and routes are
-- matched in declaration order, so a literal route declared first wins.

local util = require("lunar.core.util")

local router = {}

local Router = {}
Router.__index = Router

local function compile(path)
  local names = {}
  local pattern = { "^" }
  local position = 1
  while position <= #path do
    local char = path:sub(position, position)
    if char == ":" then
      local name = path:match("^([%w_]+)", position + 1)
      if not name then error("router: ':' with no name in " .. path) end
      names[#names + 1] = name
      -- Non-greedy, so a literal suffix in the same segment still matches.
      pattern[#pattern + 1] = "([^/]-)"
      position = position + 1 + #name
    elseif char == "*" then
      local name = path:match("^([%w_]*)", position + 1)
      names[#names + 1] = name ~= "" and name or "rest"
      pattern[#pattern + 1] = "(.*)"
      position = position + 1 + #name
    else
      pattern[#pattern + 1] = util.pattern_escape(char)
      position = position + 1
    end
  end
  pattern[#pattern + 1] = "$"
  return table.concat(pattern), names
end

function router.new()
  return setmetatable({ routes = {}, middleware = {} }, Router)
end

--- Middleware runs before the table, in the order it was added. Returning a
-- response stops the request there; returning nothing passes it on.
function Router:use(handler)
  self.middleware[#self.middleware + 1] = handler
  return self
end

function Router:add(methods, path, handler)
  if type(methods) == "string" then methods = { methods } end
  local pattern, names = compile(path)
  self.routes[#self.routes + 1] = {
    methods = methods, path = path, pattern = pattern, names = names, handler = handler,
  }
  return self
end

for _, method in ipairs({ "get", "post", "put", "patch", "delete", "head", "options" }) do
  Router[method] = function(self, path, handler)
    return self:add(method:upper(), path, handler)
  end
end

function Router:any(path, handler)
  return self:add("ANY", path, handler)
end

local function matches_method(route, method)
  for _, candidate in ipairs(route.methods) do
    if candidate == "ANY" or candidate == method then return true end
    if candidate == "GET" and method == "HEAD" then return true end
  end
  return false
end

--- Dispatches, and returns nil when nothing answered.
--
-- A handler that returns nil *declines* the request, and the next matching
-- route gets it. That is how a page route can sit in front of the static files
-- without knowing what is on disk.
function Router:dispatch(req)
  for _, middleware in ipairs(self.middleware) do
    local res = middleware(req)
    if res then return res end
  end

  local allowed = {}
  for _, route in ipairs(self.routes) do
    local captures = { req.path:match(route.pattern) }
    if captures[1] ~= nil or route.pattern == "^$" then
      if matches_method(route, req.method) then
        local params = {}
        for index, name in ipairs(route.names) do params[name] = captures[index] end
        req.params = params
        req.route = route.path
        local res = route.handler(req, params)
        if res then return res end
      else
        for _, method in ipairs(route.methods) do
          if method ~= "ANY" then allowed[method] = true end
        end
      end
    end
  end

  -- A path that exists for another method is a 405, not a 404: the difference
  -- is the whole reason a client gets told which methods there are.
  if next(allowed) then
    local methods = util.keys(allowed)
    if allowed.GET then methods[#methods + 1] = "HEAD" end
    table.sort(methods)
    local response = require("lunar.http.response")
    return response.text("405 Method Not Allowed\n", 405,
      { ["Allow"] = table.concat(methods, ", ") })
  end

  return nil
end

router.Router = Router
router.compile = compile

return router
