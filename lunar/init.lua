local lunar = {}

lunar.VERSION = "0.1.0"

function lunar.app(options)
  return require("lunar.site.app").new(options)
end

local function env(name, fallback)
  local value = os.getenv(name)
  if value == nil or value == "" then return fallback end
  return value
end

function lunar.rate_limit_from_env()
  local number = function(name, fallback) return tonumber(env(name, nil)) or fallback end
  return {
    enabled = env("RATE_LIMIT", "1") ~= "0",
    max_keys = number("RATE_LIMIT_MAX_KEYS", 8192),
    classes = {
      page = { capacity = number("RATE_LIMIT_PAGE_BURST", 60),
               per_second = number("RATE_LIMIT_PAGE_RATE", 2) },
      asset = { capacity = number("RATE_LIMIT_ASSET_BURST", 300),
                per_second = number("RATE_LIMIT_ASSET_RATE", 20) },
      write = { capacity = number("RATE_LIMIT_WRITE_BURST", 20),
                per_second = number("RATE_LIMIT_WRITE_RATE", 0.5) },
    },
  }
end

function lunar.serve(options)
  options = options or {}
  if options.rate_limit == nil then options.rate_limit = lunar.rate_limit_from_env() end
  local app = lunar.app(options)
  local server = require("lunar.http.server")

  server.serve({
    host = options.host or "0.0.0.0",
    port = options.port or 3000,
    handler = app:handler(),
    max_body_bytes = options.max_body_bytes,
    max_connections = options.max_connections,
    max_connections_per_ip = options.max_connections_per_ip,
    on_ready = options.on_ready or function()
      io.write(string.format("lunar %s listening on http://%s:%d (%s)\n",
        lunar.VERSION, options.host or "0.0.0.0", options.port or 3000,
        app.dev and "dev" or "production"))
      io.flush()
    end,
  })

  return app
end

return lunar
