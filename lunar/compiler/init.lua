--- The compiler entry point: a `.lunar` file in, a Lua module out.
--
-- There is no build step. A component is compiled the first time it is asked
-- for and kept, and in development it is recompiled when the file on disk
-- changes. The generated module is plain readable Lua — `bin/lunar compile`
-- prints it — because the first thing anyone debugging a template wants is to
-- see what it became.

local codegen = require("lunar.compiler.codegen")
local css_lib = require("lunar.compiler.css")
local parser = require("lunar.compiler.parser")
local resolve = require("lunar.compiler.resolve")
local sfc = require("lunar.compiler.sfc")
local util = require("lunar.core.util")

local compiler = {}

-- The components a route directory is made of. Their name on their own says
-- nothing — every route has a `page` — so they are named after the directory
-- they sit in, which is the URL they draw.
local ROUTE_COMPONENTS = { page = true, shell = true, eclipse = true }

local function component_name(path)
  local base = (path or "component"):match("([^/]+)%.lunar$") or "component"
  if ROUTE_COMPONENTS[base] then
    local directory = path:match("([^/]+)/[%w_%-]+%.lunar$")
    return (directory and (directory .. "/") or "") .. base
  end
  return base
end

--- Source in, the Lua source of a module out.
function compiler.compile(source, options)
  options = options or {}
  local path = options.path or "component.lunar"
  local filename = options.filename or path

  local parts = sfc.split(source, filename)
  local ast = parser.parse(parts.template, { filename = filename })

  local scope_class, scoped_css = nil, ""
  if util.trim(parts.style) ~= "" then
    -- The class is derived from the path and the styles, so two components
    -- never collide and the same component always gets the same class — which
    -- is what makes the generated CSS stable across restarts.
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

--- Compiles and loads, returning the component. The chunk is named after the
-- `.lunar` file, so a traceback points at the component and not at a string.
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

-- The cache -------------------------------------------------------------------

local Cache = {}
Cache.__index = Cache

--- `watch` recompiles when the file's bytes change, which is what development
-- wants; without it a component is compiled once per process, which is what a
-- deploy wants. There is no mtime call because there is no way to make one
-- without a C module, and reading a file that is already in the page cache is
-- cheaper than the process that would be.
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

--- Resolves `import("./Card.lunar")` from inside a component. Relative to the
-- importing file, or to the project root when it starts with `/`. The path
-- arithmetic is `compiler.resolve`, which the browser bundle uses too, so an
-- import means the same file in both halves.
function Cache:resolve(request, from)
  return self:get(resolve.path(request, from, self.root))
end

--- Installs this cache as the one `import()` uses.
function Cache:install()
  local component = require("lunar.runtime.component")
  component.resolver = function(request, from) return self:resolve(request, from) end
  return self
end

compiler.Cache = Cache
compiler.component_name = component_name

return compiler
