--- The filesystem, as far as Lua can see it.
--
-- Reading and writing a file is standard library. Listing a directory and
-- creating one are not: there is no way to do either in Lua 5.4 without a C
-- module, and this framework has one dependency and it is LuaSocket. So those
-- two shell out, and they are the only two places in the framework that do.
--
-- It matters that both are build-time: route discovery at boot, and `mkdirp`
-- when a deploy target is generated. A request never shells out.

local util = require("lunar.core.util")

local fs = {}

fs.read = util.read_file
fs.write = util.write_file
fs.exists = util.file_exists

--- Quotes a path for the shell. Single quotes, with the only escape a POSIX
-- shell has for them, so a directory with a quote in its name cannot become
-- a command.
local function quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

--- Creates a directory and its parents, for a target being generated.
--
-- The second and last shell-out in the framework, and like the first it
-- happens at build time: a request never reaches either.
function fs.mkdirp(path)
  local ok = os.execute("mkdir -p " .. quote(path))
  return ok == true or ok == 0
end

--- Copies a file, bytes as they are.
function fs.copy(from, to)
  local source = fs.read(from)
  if source == nil then return false, from .. ": no such file" end
  fs.mkdirp(fs.dirname(to))
  if not fs.write(to, source) then return false, to .. ": could not be written" end
  return true
end

--- Every file under `root`, as paths relative to it. Depth-first and sorted,
-- so route discovery is the same on every machine.
function fs.files(root)
  local out = {}
  local pipe = io.popen("find " .. quote(root) .. " -type f -print 2>/dev/null")
  if not pipe then return out end
  local prefix = root:gsub("/+$", "") .. "/"
  for line in pipe:lines() do
    if util.starts_with(line, prefix) then
      out[#out + 1] = line:sub(#prefix + 1)
    end
  end
  pipe:close()
  table.sort(out)
  return out
end

function fs.is_directory(path)
  -- A directory opens but cannot be read, which is the one portable way to
  -- tell the two apart without a stat.
  local handle = io.open(path, "rb")
  if not handle then return false end
  local _, err = handle:read(1)
  handle:close()
  return err ~= nil and err ~= "" or false
end

function fs.join(...)
  local parts = {}
  for index = 1, select("#", ...) do
    local piece = select(index, ...)
    if piece and piece ~= "" then
      parts[#parts + 1] = (piece:gsub("/+$", ""))
    end
  end
  return (table.concat(parts, "/"):gsub("//+", "/"))
end

--- The directory a path is in, which is what a relative import resolves
-- against.
function fs.dirname(path)
  return path:match("^(.*)/[^/]*$") or "."
end

function fs.basename(path)
  return path:match("([^/]+)$") or path
end

return fs
