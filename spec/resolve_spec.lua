local resolve = require("lunar.compiler.resolve")

local T = {}

function T.normalises_a_path_without_eating_the_parents_of_the_root()
  local cases = {
    { "app/orbit/./page.lunar", "app/orbit/page.lunar" },
    { "./app/orbit", "app/orbit" },
    { "app/lib/../orbit", "app/orbit" },
    { "../../tmp/app", "../../tmp/app" },
    { "../../tmp/app/orbit/../lib", "../../tmp/app/lib" },
    { "/srv/app//orbit/", "/srv/app/orbit" },
    { "/srv/../app", "/app" },
    { "/..", "/" },
    { "..", ".." },
    { ".", "." },
    { "", "" },
  }
  for _, case in ipairs(cases) do
    local got = resolve.normalize(case[1])
    assert(got == case[2], string.format("%q became %q, wanted %q", case[1], got, case[2]))
  end
end

function T.resolves_an_import_against_the_file_that_asked()
  local cases = {
    { "./Card.lunar", "app/orbit/page.lunar", "app", "app/orbit/Card.lunar" },
    { "../lib/Card.lunar", "app/orbit/page.lunar", "app", "app/lib/Card.lunar" },
    { "../../shared/Card.lunar", "app/orbit/deep/page.lunar", "app", "app/shared/Card.lunar" },
    { "/lib/Nav.lunar", "app/orbit/page.lunar", "app", "app/lib/Nav.lunar" },
    { "/lib/Nav.lunar", "/srv/app/orbit/page.lunar", "/srv/app", "/srv/app/lib/Nav.lunar" },
    { "./Card", "app/orbit/page.lunar", "app", "app/orbit/Card.lunar" },
  }
  for _, case in ipairs(cases) do
    local got = resolve.path(case[1], case[2], case[3])
    assert(got == case[4], string.format("%s from %s became %s, wanted %s",
      case[1], case[2], got, case[4]))
  end
end

function T.an_app_reached_through_its_parent_resolves_like_any_other()
  local root = "../../tmp/app"
  local from = root .. "/orbit/page.lunar"

  assert(resolve.path("./Card.lunar", from, root) == root .. "/orbit/Card.lunar")
  assert(resolve.path("/lib/Nav.lunar", from, root) == root .. "/lib/Nav.lunar")
  assert(resolve.module_name(root .. "/orbit/./Card.lunar")
    == resolve.module_name(root .. "/orbit/Card.lunar"),
    "the same component is the same module whichever way it is spelled")
end

function T.the_registry_finds_a_component_however_the_path_is_spelled()
  local registry = {
    root = "app",
    components = { ["app/lib/Card.lunar"] = "lunar.app:app/lib/Card.lunar" },
  }
  package.preload["lunar.app:app/lib/Card.lunar"] = function()
    return { lunar_component = true, name = "Card" }
  end

  local resolver = resolve.registry_resolver(registry)
  local def = resolver("/lib/Card.lunar", "app/orbit/page.lunar")
  assert(def and def.name == "Card", "the component was found")

  local same = resolver("../lib/Card.lunar", "app/orbit/page.lunar")
  assert(same and same.name == "Card", "and found the other way round too")

  local missing, err = resolver("./Nope.lunar", "app/orbit/page.lunar")
  assert(missing == nil)
  assert(err:find("app/orbit/Nope.lunar is not in the bundle", 1, true), err)

  package.preload["lunar.app:app/lib/Card.lunar"] = nil
end

return T
