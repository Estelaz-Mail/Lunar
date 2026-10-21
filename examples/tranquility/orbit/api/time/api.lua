--- An endpoint. One function per method; what it returns becomes the response,
--- and a plain table becomes JSON. A directory with an `api.lua` and no
--- `page.lunar` is a URL that is only ever data.

return {
  GET = function(event)
    return {
      now = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      route = event.route,
      asked_from = event.request.ip or "unknown",
    }
  end,

  POST = function(event)
    local body = event.request:form()
    if not body.echo then
      return { status = 422, headers = { ["Content-Type"] = "application/json" },
        body = '{"error":"send an `echo` field"}' }
    end
    return { echoed = body.echo }
  end,
}
