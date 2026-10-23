local terminal = {}

local function clean(message)
  message = tostring(message)
  while message:match("^lunar:%s*") do message = message:gsub("^lunar:%s*", "", 1) end
  return message
end

function terminal.diagnostic(message)
  message = clean(message)
  local path, line, detail = message:match("^(.-%.lunar):(%d+):%s*(.*)")
  if not path then path, line, detail = message:match("^(.-%.lua):(%d+):%s*(.*)") end
  if path then path = path:match("([^:]+)$"):match("^%s*(.-)%s*$") end
  return { file = path, line = tonumber(line), message = clean(detail or message) }
end

function terminal.new(options)
  options = options or {}
  local getenv = options.getenv or os.getenv
  local styled = getenv("LUNAR_TTY") == "1" and getenv("TERM") ~= "dumb"
    and getenv("NO_COLOR") == nil and getenv("CI") == nil
  local stream = options.stream or io.stdout
  local error_stream = options.error_stream or io.stderr
  local error_styled = getenv("LUNAR_STDERR_TTY") == "1" and getenv("TERM") ~= "dumb"
    and getenv("NO_COLOR") == nil and getenv("CI") == nil
  local function error_paint(code, value)
    if not error_styled then return tostring(value) end
    return "\27[" .. code .. "m" .. tostring(value) .. "\27[0m"
  end
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
    error = function(info)
      local red = function(value) return error_paint("91", value) end
      local dim = function(value) return error_paint("90", value) end
      local label = info.title or (info.file and info.file:match("%.lunar$") and "Compile error" or "Request error")
      error_stream:write("\n  ", red("x"), " ", error_paint("1", safe(label)), "\n")
      if info.route then error_stream:write("    ", dim(safe(info.route)), "\n") end
      if info.file then
        error_stream:write("\n    ", error_paint("94", safe(info.file)),
          info.line and (":" .. info.line) or "", "\n")
      end
      for line in (info.message .. "\n"):gmatch("([^\n]*)\n") do
        error_stream:write("    ", safe(line), "\n")
      end
      if info.source and info.line then
        local lines = {}
        for line in (info.source .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
        if lines[info.line] then
          error_stream:write("\n")
          local width = #tostring(math.min(#lines, info.line + 1))
          for number = math.max(1, info.line - 1), math.min(#lines, info.line + 1) do
            local text = safe(lines[number]:gsub("\t", "  "))
            local ok, stop = pcall(utf8.offset, text, 157)
            if ok and stop then text = text:sub(1, stop - 1) .. "..." end
            local marker = number == info.line and red(">") or " "
            error_stream:write("  ", marker, " ", dim(string.format("%" .. width .. "d", number)),
              dim(" | "), text, "\n")
          end
        end
      end
      if info.watch then error_stream:write("\n    ", dim("Waiting for changes. Save to retry."), "\n") end
      error_stream:write("\n")
      error_stream:flush()
    end,
    stopped = function()
      stream:write("\n  ", paint("94", "*"), " ", paint("90", "Back on the ground."), "\n\n")
      stream:flush()
    end,
  }
end

return terminal
