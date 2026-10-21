--- The two things a `load` function can do instead of returning data.
--
-- Both are raised, not returned, so they work from anywhere inside a load —
-- including a helper three calls deep — and a caller cannot forget to check a
-- return value.

local errors = {}

local MARKER = "lunar:control"

--- Stops rendering and shows the error page with this status.
function errors.fail(status, message)
  error(setmetatable({
    marker = MARKER, kind = "error",
    status = tonumber(status) or 500,
    message = message or "",
  }, { __tostring = function(self)
    return string.format("%d %s", self.status, self.message)
  end }), 0)
end

--- Stops rendering and sends a redirect.
function errors.redirect(status, location)
  if type(status) == "string" then status, location = 302, status end
  error(setmetatable({
    marker = MARKER, kind = "redirect",
    status = tonumber(status) or 302,
    location = location or "/",
  }, { __tostring = function(self)
    return string.format("%d %s", self.status, self.location)
  end }), 0)
end

function errors.is(value, kind)
  if type(value) ~= "table" or value.marker ~= MARKER then return false end
  return kind == nil or value.kind == kind
end

errors.MARKER = MARKER

return errors
