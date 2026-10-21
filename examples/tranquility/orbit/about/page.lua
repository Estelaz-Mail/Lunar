return {
  probe = function()
    return {
      title = "About Lunar",
      parts = {
        { path = "lunar/compiler/", what = "the .lunar splitter, parser, CSS scoper and code generator" },
        { path = "lunar/runtime/", what = "signals, the component scope, the SSR helpers, the DOM layer" },
        { path = "lunar/site/", what = "filesystem routes, the render pipeline, the client bundle" },
        { path = "lunar/http/", what = "HTTP/1.1, the router, static files, security, rate limiting" },
      },
    }
  end,
}
