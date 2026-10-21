--- Lunar.
--
--   local lunar = require("lunar")
--   lunar.serve({ root = "examples/tranquility", port = 3000 })
--
-- That is the whole public surface for running an app. Everything else is a
-- module under `lunar.` and documented where it lives.

local lunar = {}

lunar.VERSION = "0.1.0"

--- Builds an app without serving it, which is what the specs and the build
-- command use.
function lunar.app(options)
  return require("lunar.site.app").new(options)
end

--- Builds an app and serves it until stopped.
function lunar.serve(options)
  options = options or {}
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
