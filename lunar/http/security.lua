--- The security headers, including the Content Security Policy.
--
-- On by default. A framework whose safe configuration is a chapter of the
-- documentation ships unsafe apps, so the policy here starts at
-- `default-src 'none'` and an app widens it by naming what it needs.
--
-- The policy is built once, because it depends only on configuration. An
-- inline script is allowed by the **SHA-256 of its bytes**, not by a nonce: a
-- nonce has to be new for every response, and a response that sits in a cache
-- carries its nonce to every visitor, which is no protection at all. Lunar's
-- own document has no executable inline script — the page's data is a
-- `type="application/json"` block, which a browser does not run — so most apps
-- need no exception at all.

local base64 = require("lunar.core.base64")
local sha256 = require("lunar.crypto.sha256")
local util = require("lunar.core.util")

local security = {}

local Security = {}
Security.__index = Security

local PERMISSIONS_POLICY = table.concat({
  "accelerometer=()", "ambient-light-sensor=()", "autoplay=(self)", "bluetooth=()",
  "camera=()", "display-capture=()", "geolocation=()", "gyroscope=()",
  "idle-detection=()", "magnetometer=()", "microphone=()", "midi=()", "payment=()",
  "screen-wake-lock=()", "serial=()", "usb=()", "xr-spatial-tracking=()",
}, ", ")

--- The CSP source expression for an inline script, from its exact bytes: what
-- the browser hashes is what it parsed, so not a byte of it may be trimmed.
function security.hash_source(source)
  return "'sha256-" .. base64.encode(sha256.digest(source)) .. "'"
end

local function sources(list, extra)
  local out = {}
  for _, source in ipairs(list) do
    if source ~= nil and source ~= "" then out[#out + 1] = source end
  end
  for _, source in ipairs(extra or {}) do
    if source ~= nil and source ~= "" then out[#out + 1] = source end
  end
  return out
end

local function document_policy(self)
  local extra = self.extra
  local directives = {
    "default-src 'none'",
    "base-uri 'self'",
    "form-action " .. table.concat(sources({ "'self'" }, extra["form-action"]), " "),
    "frame-ancestors " .. table.concat(sources({ self.frame_ancestors }, nil), " "),
    "script-src " .. table.concat(
      sources({ "'self'" }, sources(self.script_hashes, extra["script-src"])), " "),
    -- Inline `style` attributes are what `style:color={…}` and a progress bar
    -- compile to, and an attribute cannot be hashed. A stylesheet is still
    -- restricted to this origin.
    "style-src " .. table.concat(sources({ "'self'", "'unsafe-inline'" }, extra["style-src"]), " "),
    "img-src " .. table.concat(sources({ "'self'", "data:" }, extra["img-src"]), " "),
    "font-src " .. table.concat(sources({ "'self'" }, extra["font-src"]), " "),
    "media-src " .. table.concat(sources({ "'self'" }, extra["media-src"]), " "),
    -- Fengari fetches each `type="application/lua"` script with XHR, which is
    -- `connect-src` and not `script-src`.
    "connect-src " .. table.concat(sources({ "'self'" }, extra["connect-src"]), " "),
    -- Nothing may be framed unless the app names something, in which case
    -- `'none'` would contradict it.
    "frame-src " .. table.concat(
      #(extra["frame-src"] or {}) > 0 and extra["frame-src"] or { "'none'" }, " "),
    "worker-src 'self'",
    "manifest-src 'self'",
  }
  if self.report_uri ~= "" then
    directives[#directives + 1] = "report-uri " .. self.report_uri
  end
  return table.concat(directives, "; ")
end

local function resource_policy(self)
  -- A response that is not a document may not act as one: nothing loads,
  -- nothing frames it, and it is sandboxed if a browser navigates to it.
  local policy = "default-src 'none'; frame-ancestors 'none'; sandbox"
  if self.report_uri ~= "" then policy = policy .. "; report-uri " .. self.report_uri end
  return policy
end

--- `options` is `{ enabled, inline_scripts, extra, frame_ancestors, hsts_max_age,
-- hsts_include_subdomains, hsts_preload, report_uri, report_only }`.
--
-- `extra` is how an app widens one directive without rewriting the policy:
-- `{ ["img-src"] = { "https://images.example" } }`.
function security.new(options)
  options = options or {}

  local hashes = {}
  for _, source in ipairs(options.inline_scripts or {}) do
    hashes[#hashes + 1] = security.hash_source(source)
  end

  local self = setmetatable({
    enabled = options.enabled ~= false,
    script_hashes = hashes,
    extra = options.extra or {},
    frame_ancestors = options.frame_ancestors or "'self'",
    hsts_max_age = math.floor(tonumber(options.hsts_max_age) or 15552000),
    hsts_include_subdomains = options.hsts_include_subdomains ~= false,
    hsts_preload = options.hsts_preload or false,
    report_uri = options.report_uri or "",
    report_only = options.report_only or false,
  }, Security)

  self.header_name = self.report_only
    and "Content-Security-Policy-Report-Only" or "Content-Security-Policy"
  self.document_policy = document_policy(self)
  self.resource_policy = resource_policy(self)
  return self
end

function Security:strict_transport_security()
  if self.hsts_max_age <= 0 then return nil end
  local value = "max-age=" .. tostring(self.hsts_max_age)
  if self.hsts_include_subdomains then value = value .. "; includeSubDomains" end
  if self.hsts_preload then value = value .. "; preload" end
  return value
end

function Security:headers(res, req)
  local content_type = (res.headers or {})["Content-Type"] or ""
  local is_document = util.starts_with(content_type:lower(), "text/html")

  local headers = {
    [self.header_name] = is_document and self.document_policy or self.resource_policy,
    ["X-Content-Type-Options"] = "nosniff",
    ["Referrer-Policy"] = "strict-origin-when-cross-origin",
    ["Cross-Origin-Resource-Policy"] = "same-origin",
  }

  if is_document then
    headers["X-Frame-Options"] = self.frame_ancestors == "'none'" and "DENY" or "SAMEORIGIN"
    headers["Cross-Origin-Opener-Policy"] = "same-origin"
    headers["Permissions-Policy"] = PERMISSIONS_POLICY
  end

  -- Only over TLS. Sent on a plain request it is ignored by a conforming
  -- browser, and an unconditional one would pin a developer's whole localhost
  -- to HTTPS for the length of the max-age.
  if req and req.scheme == "https" then
    headers["Strict-Transport-Security"] = self:strict_transport_security()
  end

  return headers
end

--- Adds the headers to a response, in place. A header the handler already set
-- wins, so a route that needs a looser policy can say so.
function Security:apply(res, req)
  if not self.enabled or type(res) ~= "table" then return res end
  res.headers = res.headers or {}
  for name, value in pairs(self:headers(res, req)) do
    if value ~= nil and res.headers[name] == nil then res.headers[name] = value end
  end
  return res
end

function Security:wrap(handler)
  return function(req)
    return self:apply(handler(req), req)
  end
end

security.Security = Security
security.PERMISSIONS_POLICY = PERMISSIONS_POLICY

return security
