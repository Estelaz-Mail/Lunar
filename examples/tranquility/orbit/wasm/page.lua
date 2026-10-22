return {
  probe = function()
    return {
      title = "Lua in wasm",
      parts = {
        { name = "geometry", what = "area and hypotenuse, compiled from wasm/geometry.lua" },
        { name = "series", what = "basel and rings, which call geometry" },
      },
    }
  end,
}
