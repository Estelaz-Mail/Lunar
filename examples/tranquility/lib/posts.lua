local posts = {
  {
    slug = "why-lua",
    title = "Why Lua, for both halves",
    date = "2026-02-11",
    body = "<p>One language on the server and in the browser is not a trick: "
      .. "Fengari is a Lua virtual machine in JavaScript, so the component "
      .. "that rendered your HTML is the component that now runs in your tab.</p>",
  },
  {
    slug = "globals-are-state",
    title = "A global in a component script is state",
    date = "2026-03-02",
    body = "<p>The compiler emits a component's script as "
      .. "<code>function(_ENV) … end</code>. An undeclared assignment is "
      .. "therefore a write to the component's scope, which is a signal. "
      .. "<code>count = count + 1</code> is reactive because Lua said so.</p>",
  },
  {
    slug = "no-build-step",
    title = "No build step, on purpose",
    date = "2026-04-19",
    body = "<p>Components compile in memory, on demand, cached by their own "
      .. "bytes. There is no <code>dist/</code> to go stale and no generated "
      .. "file in the repository.</p>",
  },
}

local by_slug = {}
for _, post in ipairs(posts) do by_slug[post.slug] = post end

return { all = posts, get = function(slug) return by_slug[slug] end }
