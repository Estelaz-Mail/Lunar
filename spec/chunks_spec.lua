local chunks = require("lunar.site.chunks")

local T = {}

local function loader(sources)
  local asked = {}
  local warnings = {}
  local instance = chunks.loader({
    warn = function(message) warnings[#warnings + 1] = message end,
    fetch_text = function(url, on_text, on_error)
      asked[#asked + 1] = url
      local source = sources[url]
      if source == nil then return on_error() end
      on_text(source)
    end,
  })
  return instance, asked, warnings
end

function T.runs_a_chunk_once_and_remembers_it()
  _G.LUNAR_SPEC_CHUNK = 0
  local instance, asked = loader({
    ["/_lunar/chunk/a.lua"] = "LUNAR_SPEC_CHUNK = LUNAR_SPEC_CHUNK + 1",
  })

  local arrived = 0
  instance:ensure("/_lunar/chunk/a.lua", function() arrived = arrived + 1 end)
  instance:ensure("/_lunar/chunk/a.lua", function() arrived = arrived + 1 end)

  assert(arrived == 2, "both callers carried on")
  assert(#asked == 1, "but the chunk was fetched once")
  assert(_G.LUNAR_SPEC_CHUNK == 1, "and run once")
  _G.LUNAR_SPEC_CHUNK = nil
end

function T.carries_on_at_once_for_a_chunk_the_page_already_has()
  local instance, asked = loader({})
  instance:hold("/_lunar/chunk/held.lua")

  local arrived = false
  instance:ensure("/_lunar/chunk/held.lua", function() arrived = true end)
  assert(arrived, "it did not wait")
  assert(#asked == 0, "and asked for nothing")
end

function T.carries_on_when_a_route_has_no_chunk_of_its_own()
  local instance, asked = loader({})
  local arrived = false
  instance:ensure(nil, function() arrived = true end)
  assert(arrived and #asked == 0, "nothing to load is not a failure")
end

function T.gives_up_when_the_chunk_cannot_be_fetched()
  local instance = loader({})
  local arrived, gave_up = false, false
  instance:ensure("/_lunar/chunk/missing.lua",
    function() arrived = true end,
    function() gave_up = true end)
  assert(not arrived and gave_up, "a miss hands the navigation back")
end

function T.gives_up_on_a_chunk_that_does_not_parse()
  local instance, _, warnings = loader({ ["/c.lua"] = "this is not lua ((" })
  local arrived, gave_up = false, false
  instance:ensure("/c.lua", function() arrived = true end, function() gave_up = true end)

  assert(not arrived and gave_up)
  assert(instance:has("/c.lua") == false, "and it is not remembered")
  assert(warnings[1]:find("did not parse", 1, true), warnings[1])
end

function T.gives_up_on_a_chunk_that_fails_while_running()
  local instance, _, warnings = loader({ ["/c.lua"] = "error('no')" })
  local gave_up = false
  instance:ensure("/c.lua", function() end, function() gave_up = true end)

  assert(gave_up)
  assert(warnings[1]:find("did not run", 1, true), warnings[1])
end

function T.gives_up_when_there_is_nothing_to_fetch_with()
  local instance = chunks.loader({})
  local gave_up = false
  instance:ensure("/c.lua", function() end, function() gave_up = true end)
  assert(gave_up, "without a fetch there is no chunk")
end

function T.installs_what_the_chunk_declares()
  local instance = loader({
    ["/c.lua"] = 'package.preload["lunar.spec.chunk"] = function() return 42 end',
  })
  instance:ensure("/c.lua", function() end)

  assert(require("lunar.spec.chunk") == 42, "the module the chunk carried is loadable")
  package.loaded["lunar.spec.chunk"] = nil
  package.preload["lunar.spec.chunk"] = nil
end

local function with_app(script, options, run)
  local fs = require("lunar.core.fs")
  local util = require("lunar.core.util")
  local root = os.tmpname()
  os.remove(root)
  local files = {
    ["orbit/page.lunar"] = "<script>" .. script .. "</script><Shared />",
    ["orbit/other/page.lunar"] = '<script>local Shared = import("/lib/Shared.lunar")</script><Shared />',
    ["lib/Shared.lunar"] = "<p>shared component</p>",
  }
  for relative, source in pairs(files) do
    local path = fs.join(root, relative)
    fs.mkdirp(fs.dirname(path))
    assert(util.write_file(path, source))
  end
  local config = { root = root, dev = false, split = true }
  for key, value in pairs(options or {}) do config[key] = value end
  local ok, message = pcall(function() run(require("lunar").app(config), root) end)
  os.execute("rm -rf " .. root)
  assert(ok, message)
end

local function render_chunk(app)
  local bundle = require("lunar.site.bundle")
  local environment = setmetatable({ package = { preload = {}, loaded = {} } }, { __index = _G })
  environment.load = function(source, name, mode, env)
    return load(source, name, mode or "t", env or environment)
  end
  environment.require = function(name)
    local loaded = environment.package.loaded
    if loaded[name] ~= nil then return loaded[name] end
    local loader = assert(environment.package.preload[name], "missing browser module: " .. name)
    local value = loader(name)
    loaded[name] = value == nil and true or value
    return loaded[name]
  end
  local pieces = assert(bundle.chunks(app))
  assert(environment.load(assert(pieces["/"]).source))()
  local registry = assert(environment.load(assert(bundle.build(app))))()
  local moonlight = environment.require("lunar.site.moonlight")
  moonlight.install_resolver(registry)
  local definitions = assert(moonlight.chain_for(registry, "/"))
  return environment.require("lunar.runtime.component").render(definitions[1], { data = {} }, {})
end

function T.splits_shorthand_and_commented_imports_without_losing_shared_components()
  for _, script in ipairs({
    'local Shared = import "/lib/Shared.lunar"',
    'local Shared = import [=[/lib/Shared.lunar]=]',
    'local Shared = import -- argument follows\n("/lib/Shared.lunar")',
    'local Shared = import --[=[comment]=] [=[/lib/Shared.lunar]=]',
    'local Shared = import("/lib/\\083hared.lunar")',
  }) do
    with_app(script, {}, function(app)
      assert(require("lunar.site.bundle").plan(app).split, script)
      assert(render_chunk(app):find("<p>shared component</p>", 1, true), script)
    end)
  end
end

function T.ignores_import_text_inside_strings_and_comments()
  with_app([==[
local example = [=[import("/lib/Missing.lunar")]=]
-- import("/lib/Missing.lunar")
local Shared = import("/lib/Shared.lunar")
]==], {}, function(app)
    assert(require("lunar.site.bundle").plan(app).split)
    assert(render_chunk(app):find("<p>shared component</p>", 1, true))
  end)
end

function T.falls_back_to_a_complete_bundle_for_aliased_imports()
  with_app('local resolve = import; local Shared = resolve("/lib/Shared.lunar")', {}, function(app)
    local bundle = require("lunar.site.bundle")
    assert(not bundle.plan(app).split)
    assert(next(bundle.chunks(app)) == nil)
    assert(app:chunk_url("/") == nil)
  end)
end

function T.disabling_split_omits_chunks_from_native_and_frozen_apps()
  with_app('local Shared = import("/lib/Shared.lunar")', { split = false }, function(app)
    local bundle = require("lunar.site.bundle")
    local json = require("lunar.core.json")
    assert(next(bundle.chunks(app)) == nil)
    assert(app:chunk_url("/") == nil)
    for path in pairs(app:client_integrity().assets) do
      assert(not path:find(bundle.CHUNKS, 1, true))
    end
    local server = assert(bundle.server(app))
    local fetch = assert(load(server))()
    local answer = json.decode(fetch(json.encode({
      method = "GET", url = "https://lunar.test/", headers = { accept = "application/json" },
    })))
    assert(answer.status == 200)
    assert(json.decode(answer.body).chunk == nil)
  end)
end

return T
