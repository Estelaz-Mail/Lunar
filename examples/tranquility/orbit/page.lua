return {
  probe = function(event)
    return {
      title = "Lunar — a framework in Lua",
      start = tonumber(event.url.query.start) or 0,
      facts = {
        { name = "runtime", value = _VERSION },
        { name = "route", value = event.route },
        { name = "method", value = event.request.method },
        { name = "dependencies", value = "LuaSocket, for the sockets" },
      },
    }
  end,
}
