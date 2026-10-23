local fs = require("lunar.core.fs")
local util = require("lunar.core.util")

local routes = {}

local PAGE = "page.lunar"
local PAGE_PROBE = "page.lua"
local SHELL = "shell.lunar"
local SHELL_PROBE = "shell.lua"
local ENDPOINT = "api.lua"
local ECLIPSE = "eclipse.lunar"

routes.FILES = {
  [PAGE] = "page", [PAGE_PROBE] = "probe",
  [SHELL] = "shell", [SHELL_PROBE] = "shell_probe",
  [ENDPOINT] = "endpoint", [ECLIPSE] = "eclipse",
}

local function route_id(directory)
  if directory == "" then return "/" end
  local segments = {}
  for segment in directory:gmatch("[^/]+") do
    if not segment:match("^%(.*%)$") then segments[#segments + 1] = segment end
  end
  if #segments == 0 then return "/" end
  return "/" .. table.concat(segments, "/")
end

local function compile(id)
  local segments = {}
  for segment in id:gmatch("[^/]+") do
    local rest = segment:match("^%[%.%.%.([%w_]+)%]$")
    local param = segment:match("^%[([%w_]+)%]$")
    if rest then
      segments[#segments + 1] = { kind = "rest", name = rest }
    elseif param then
      segments[#segments + 1] = { kind = "param", name = param }
    else
      segments[#segments + 1] = { kind = "literal", value = segment }
    end
  end
  return segments
end

function routes.match_segments(segments, path_segments)
  local params = {}
  local index = 1
  for _, segment in ipairs(segments) do
    if segment.kind == "rest" then
      local tail = {}
      for position = index, #path_segments do tail[#tail + 1] = path_segments[position] end
      params[segment.name] = table.concat(tail, "/")
      return params
    end
    local value = path_segments[index]
    if value == nil then return nil end
    if segment.kind == "literal" then
      if value ~= segment.value then return nil end
    else
      params[segment.name] = value
    end
    index = index + 1
  end
  if index <= #path_segments then return nil end
  return params
end

local function specificity(segments)
  local literals, params, rest = 0, 0, 0
  for _, segment in ipairs(segments) do
    if segment.kind == "literal" then literals = literals + 1
    elseif segment.kind == "param" then params = params + 1
    else rest = rest + 1 end
  end
  return { rest = rest, literals = literals, params = params, length = #segments }
end

function routes.discover(root)
  local files = fs.files(root)
  local directories = {}

  local function directory_of(path)
    local directory = path:match("^(.*)/[^/]*$") or ""
    directories[directory] = directories[directory] or {}
    return directories[directory]
  end

  for _, path in ipairs(files) do
    local name = fs.basename(path)
    local entry = directory_of(path)
    if name == PAGE then entry.page = path
    elseif name == PAGE_PROBE then entry.page_probe = path
    elseif name == SHELL then entry.shell = path
    elseif name == SHELL_PROBE then entry.shell_probe = path
    elseif name == ENDPOINT then entry.endpoint = path
    elseif name == ECLIPSE then entry.eclipse = path
    end
  end

  local function chain(directory, field)
    local out = {}
    local walked = ""
    local entry = directories[""] or {}
    if entry[field] then out[#out + 1] = entry[field] end
    for segment in directory:gmatch("[^/]+") do
      walked = walked == "" and segment or (walked .. "/" .. segment)
      local current = directories[walked]
      if current and current[field] then out[#out + 1] = current[field] end
    end
    return out
  end

  local function levels_for(directory, entry)
    local out = {}
    local walked = ""

    local function add(current)
      if not current then return end
      if current.shell or current.shell_probe then
        out[#out + 1] = {
          component = current.shell and fs.join(root, current.shell) or nil,
          probe = current.shell_probe and fs.join(root, current.shell_probe) or nil,
        }
      end
    end

    add(directories[""])
    for segment in directory:gmatch("[^/]+") do
      walked = walked == "" and segment or (walked .. "/" .. segment)
      if walked ~= "" and directory ~= "" then add(directories[walked]) end
    end

    out[#out + 1] = {
      component = entry.page and fs.join(root, entry.page) or nil,
      probe = entry.page_probe and fs.join(root, entry.page_probe) or nil,
      page = true,
    }
    return out
  end

  local list = {}
  for directory, entry in pairs(directories) do
    if entry.page or entry.endpoint then
      local id = route_id(directory)
      local segments = compile(id)
      local eclipses = chain(directory, "eclipse")
      list[#list + 1] = {
        id = id,
        directory = directory,
        segments = segments,
        specificity = specificity(segments),
        page = entry.page and fs.join(root, entry.page) or nil,
        page_probe = entry.page_probe and fs.join(root, entry.page_probe) or nil,
        endpoint = entry.endpoint and fs.join(root, entry.endpoint) or nil,
        levels = levels_for(directory, entry),
        eclipse = eclipses[#eclipses] and fs.join(root, eclipses[#eclipses]) or nil,
      }
    end
  end

  table.sort(list, function(a, b)
    local x, y = a.specificity, b.specificity
    local rank = { literal = 3, param = 2, rest = 1 }
    for index = 1, math.min(#a.segments, #b.segments) do
      local left, right = a.segments[index], b.segments[index]
      if left.kind ~= right.kind then return rank[left.kind] > rank[right.kind] end
    end
    if x.rest ~= y.rest then return x.rest < y.rest end
    if x.literals ~= y.literals then return x.literals > y.literals end
    if x.params ~= y.params then return x.params < y.params end
    if x.length ~= y.length then return x.length > y.length end
    return a.id < b.id
  end)

  return list
end

function routes.match(list, path)
  local path_segments = {}
  for segment in path:gmatch("[^/]+") do path_segments[#path_segments + 1] = segment end
  for _, route in ipairs(list) do
    local params = routes.match_segments(route.segments, path_segments)
    if params then return route, params end
  end
  return nil
end

function routes.eclipse_for(list, path)
  local route = routes.match(list, path)
  if route and route.eclipse then return route.eclipse end
  for _, candidate in ipairs(list) do
    if candidate.id == "/" and candidate.eclipse then return candidate.eclipse end
  end
  for _, candidate in ipairs(list) do
    if candidate.eclipse then return candidate.eclipse end
  end
  return nil
end

routes.compile = compile
routes.route_id = route_id

return routes
