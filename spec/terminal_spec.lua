local terminal = require("lunar.core.terminal")

local T = {}

local function draw(environment)
  local output = {}
  local stream = {
    write = function(_, ...)
      for index = 1, select("#", ...) do output[#output + 1] = select(index, ...) end
    end,
    flush = function() end,
  }
  local screen = terminal.new({ stream = stream, getenv = function(name) return environment[name] end })
  screen.ready({ version = "1.0.0", root = "project\27[31m\r", routes = 3,
    url = "http://127.0.0.1:3000" })
  screen.stopped()
  return table.concat(output)
end

function T.keeps_redirected_and_accessible_output_free_of_terminal_controls()
  for _, environment in ipairs({ {}, { LUNAR_TTY = "0", TERM = "xterm" },
    { LUNAR_TTY = "1", TERM = "dumb" },
    { LUNAR_TTY = "1", TERM = "xterm", NO_COLOR = "1" },
    { LUNAR_TTY = "1", TERM = "xterm", CI = "true" } }) do
    local output = draw(environment)
    assert(not output:find("\27", 1, true))
    assert(not output:find("\r", 1, true))
    assert(output:find("http://127.0.0.1:3000", 1, true))
    assert(output:find("Ready for orbit.", 1, true))
  end
end

function T.styles_interactive_output_without_interpreting_user_supplied_escape_sequences()
  local output = draw({ LUNAR_TTY = "1", TERM = "xterm-256color", LANG = "en_US.UTF-8" })
  assert(output:find("\27[", 1, true))
  assert(output:find("◐", 1, true))
  assert(not output:find("\27[31m", 1, true))
  assert(output:find("project?[31m?/orbit", 1, true))
end

return T
