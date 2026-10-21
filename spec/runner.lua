--- The test runner.
--
-- `bin/lunar spec` runs every `spec/*_spec.lua`; naming one runs only that.
-- A spec file returns a table of `name -> function`; a failure is any error
-- raised inside one, so plain `assert` is the whole assertion library.

local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or ".")
package.path = root .. "/../?.lua;" .. root .. "/../?/init.lua;"
  .. root .. "/?.lua;" .. package.path

local function spec_files(names)
  if #names > 0 then
    local out = {}
    for _, name in ipairs(names) do
      out[#out + 1] = name:match("_spec%.lua$") and name or (root .. "/" .. name .. "_spec.lua")
    end
    return out
  end
  local out = {}
  -- The one shell-out in the test runner, for the one thing Lua cannot do:
  -- list a directory.
  local pipe = io.popen("ls " .. root .. "/*_spec.lua 2>/dev/null")
  if pipe then
    for line in pipe:lines() do out[#out + 1] = line end
    pipe:close()
  end
  table.sort(out)
  return out
end

local passed, failed = 0, 0
local failures = {}

for _, file in ipairs(spec_files({ ... })) do
  local chunk, load_error = loadfile(file)
  if not chunk then
    failed = failed + 1
    failures[#failures + 1] = { name = file, message = load_error }
  else
    local ok, suite = pcall(chunk)
    if not ok then
      failed = failed + 1
      failures[#failures + 1] = { name = file, message = tostring(suite) }
    else
      local names = {}
      for name in pairs(suite) do names[#names + 1] = name end
      table.sort(names)
      local label = file:match("([^/]+)_spec%.lua$")
      for _, name in ipairs(names) do
        local succeeded, err = pcall(suite[name])
        if succeeded then
          passed = passed + 1
        else
          failed = failed + 1
          failures[#failures + 1] = { name = label .. ": " .. name, message = tostring(err) }
        end
      end
    end
  end
end

for _, failure in ipairs(failures) do
  io.write("FAIL  ", failure.name, "\n      ", failure.message:gsub("\n", "\n      "), "\n")
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
