local util = require("lunar.core.util")

local fs = {}

fs.read = util.read_file
fs.write = util.write_file
fs.exists = util.file_exists

local function quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

function fs.mkdirp(path)
  local ok = os.execute("mkdir -p " .. quote(path))
  return ok == true or ok == 0
end

function fs.copy(from, to)
  local source = fs.read(from)
  if source == nil then return false, from .. ": no such file" end
  fs.mkdirp(fs.dirname(to))
  if not fs.write(to, source) then return false, to .. ": could not be written" end
  return true
end

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

function fs.dirname(path)
  return path:match("^(.*)/[^/]*$") or "."
end

function fs.basename(path)
  return path:match("([^/]+)$") or path
end

return fs
