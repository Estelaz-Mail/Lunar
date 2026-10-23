local terminal = {}

function terminal.new(options)
  options = options or {}
  local getenv = options.getenv or os.getenv
  local styled = getenv("LUNAR_TTY") == "1" and getenv("TERM") ~= "dumb"
    and getenv("NO_COLOR") == nil and getenv("CI") == nil
  local stream = options.stream or io.stdout
  local function paint(code, value)
    if not styled then return tostring(value) end
    return "\27[" .. code .. "m" .. tostring(value) .. "\27[0m"
  end
  local function safe(value)
    return tostring(value):gsub("[%z\1-\31\127]", "?")
  end
  return {
    ready = function(info)
      local locale = getenv("LC_ALL") or getenv("LC_CTYPE") or getenv("LANG") or ""
      local moon = styled and locale:lower():find("utf%-?8") and "◐" or "*"
      local blue = function(value) return paint("94", value) end
      local dim = function(value) return paint("90", value) end
      local label = function(name, value)
        stream:write("    ", dim(string.format("%-8s", name)), safe(value), "\n")
      end
      stream:write("\n  ", blue(moon), " ", paint("1", "lunar"), " ", dim(safe(info.version)),
        "  ", blue("development"), "\n\n")
      label("Local", info.url)
      label("Orbit", info.root .. "/orbit")
      label("Routes", info.routes)
      stream:write("\n    ", blue("Ready for orbit."), " ", dim("Watching for changes."),
        "\n    ", dim("Ctrl+C to land."), "\n\n")
      stream:flush()
    end,
    stopped = function()
      stream:write("\n  ", paint("94", "*"), " ", paint("90", "Back on the ground."), "\n\n")
      stream:flush()
    end,
  }
end

return terminal
