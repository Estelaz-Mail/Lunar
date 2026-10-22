local codegen = require("lunar.compiler.codegen")
local css_lib = require("lunar.compiler.css")
local parser = require("lunar.compiler.parser")
local resolve = require("lunar.compiler.resolve")
local sfc = require("lunar.compiler.sfc")
local util = require("lunar.core.util")

local compiler = {}

local ROUTE_COMPONENTS = { page = true, shell = true, eclipse = true }

local function component_name(path)
  local base = (path or "component"):match("([^/]+)%.lunar$") or "component"
  if ROUTE_COMPONENTS[base] then
    local directory = path:match("([^/]+)/[%w_%-]+%.lunar$")
    return (directory and (directory .. "/") or "") .. base
  end
  return base
end

function compiler.compile(source, options)
  options = options or {}
  local path = options.path or "component.lunar"
  local filename = options.filename or path

  local parts = sfc.split(source, filename)
  local ast = parser.parse(parts.template, { filename = filename })

  local scope_class, scoped_css = nil, ""
  if util.trim(parts.style) ~= "" then
    scope_class = css_lib.scope_class(path .. "\0" .. parts.style)
    scoped_css = css_lib.scope(parts.style, scope_class)
  end

  return codegen.generate(ast, {
    script = parts.script,
    script_line = parts.script_line,
    css = scoped_css,
    scope_class = scope_class,
    name = options.name or component_name(path),
    path = path,
    filename = filename,
  })
end

function compiler.load(source, options)
  options = options or {}
  local generated = compiler.compile(source, options)
  local chunk, message = load(generated, "@" .. (options.filename or options.path or "component.lunar"))
  if not chunk then
    error(string.format("lunar: the generated module for %s does not parse: %s\n%s",
      options.path or "a component", message, generated), 0)
  end
  return chunk(), generated
end


local Cache = {}
Cache.__index = Cache

function compiler.cache(options)
  options = options or {}
  return setmetatable({
    watch = options.watch ~= false,
    entries = {},
    root = options.root or ".",
  }, Cache)
end

function Cache:get(path)
  local source = util.read_file(path)
  if not source then return nil, path .. ": no such file" end

  local entry = self.entries[path]
  if entry and (not self.watch or entry.source == source) then
    return entry.component, entry.generated
  end

  local ok, component, generated = pcall(compiler.load, source, { path = path, filename = path })
  if not ok then return nil, component end

  self.entries[path] = { source = source, component = component, generated = generated }
  return component, generated
end

function Cache:resolve(request, from)
  return self:get(resolve.path(request, from, self.root))
end

function Cache:install()
  local component = require("lunar.runtime.component")
  component.resolver = function(request, from) return self:resolve(request, from) end
  return self
end

compiler.Cache = Cache
compiler.component_name = component_name

return compiler
