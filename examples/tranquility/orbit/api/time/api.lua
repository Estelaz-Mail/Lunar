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
