local lunar = require("lunar")

return {
  probe = function()
    return {
      site = "Lunar",
      version = lunar.VERSION,
      links = {
        { href = "/", label = "home" },
        { href = "/blog", label = "blog" },
        { href = "/about", label = "about" },
        { href = "/wasm", label = "wasm" },
      },
    }
  end,
}
