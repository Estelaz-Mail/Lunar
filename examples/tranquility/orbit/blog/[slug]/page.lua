local posts = require("posts")

return {
  probe = function(event)
    local post = posts.get(event.params.slug)
    if not post then
      event.fail(404, string.format("No post called “%s”.", event.params.slug))
    end
    return { title = post.title, post = post }
  end,
}
