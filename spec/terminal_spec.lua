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

local function draw_error(environment)
  local output = {}
  local stream = { write = function(_, ...)
    for index = 1, select("#", ...) do output[#output + 1] = tostring(select(index, ...)) end
  end, flush = function() end }
  local screen = terminal.new({ stream = stream, error_stream = stream,
    getenv = function(name) return environment[name] end })
  local info = terminal.diagnostic("lunar: lunar: orbit/page: orbit/page.lunar:2: lunar: </code> with no element open")
  assert(info.file == "orbit/page.lunar" and info.line == 2)
  info.source = "<h1>Example</h1>\n</code>\n<p>after</p>"
  info.route = "GET /\27[31m"
  info.watch = true
  screen.error(info)
  return table.concat(output)
end

function T.errors_show_a_source_frame_without_repeated_prefixes()
  local output = draw_error({})
  assert(output:find("Compile error", 1, true))
  assert(output:find("orbit/page.lunar:2", 1, true))
  assert(output:find("> 2 | </code>", 1, true))
  assert(output:find("Waiting for changes.", 1, true))
  assert(not output:find("lunar: lunar:", 1, true))
  assert(not output:find("\n    lunar:", 1, true))
  assert(not output:find("\27", 1, true))
end

function T.error_colors_follow_stderr_instead_of_stdout()
  local colored = draw_error({ LUNAR_STDERR_TTY = "1", TERM = "xterm" })
  assert(colored:find("\27[91m", 1, true))
  assert(not colored:find("\27[31m", 1, true))
  for _, env in ipairs({
    { LUNAR_TTY = "1", LUNAR_STDERR_TTY = "0", TERM = "xterm" },
    { LUNAR_STDERR_TTY = "1", TERM = "dumb" },
    { LUNAR_STDERR_TTY = "1", TERM = "xterm", NO_COLOR = "1" },
    { LUNAR_STDERR_TTY = "1", TERM = "xterm", CI = "true" },
  }) do assert(not draw_error(env):find("\27", 1, true)) end
end

return T
