local posts = require("posts")

return {
  --- A probe that cannot answer raises. `event.fail` stops the render and
  --- shows the nearest eclipse with that status; nothing downstream has to
  --- check a return value.
  probe = function(event)
    local post = posts.get(event.params.slug)
    if not post then
      event.fail(404, string.format("No post called “%s”.", event.params.slug))
    end
    return { title = post.title, post = post }
  end,
}
