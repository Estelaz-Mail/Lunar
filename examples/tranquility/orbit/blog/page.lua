local posts = require("posts")

return {
  probe = function()
    local out = {}
    for index, post in ipairs(posts.all) do
      out[index] = { slug = post.slug, title = post.title, date = post.date }
    end
    return { title = "Blog", posts = out }
  end,
}
