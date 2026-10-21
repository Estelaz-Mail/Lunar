--- A probe is what a page sends ahead of itself: it runs on the server, on
--- every request, before anything is drawn. What it brings back is the page's
--- `data` prop, and it is serialised into the document so the browser half
--- starts from the same values rather than fetching them all over again.

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
