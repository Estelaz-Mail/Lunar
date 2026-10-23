local analyze = require("lunar.analyze")
local bundle = require("lunar.site.bundle")
local lunar = require("lunar")

local T = {}

local function result()
  return assert(analyze.run("examples/tranquility"))
end

function T.accounts_for_every_part_of_the_bundle()
  local found = result()
  local total = 0
  for _, item in ipairs(found.parts) do total = total + item.bytes end

  assert(#found.parts > 0, "a bundle has parts")
  assert(total <= found.moonlight.bytes, "a part cannot weigh more than the whole")
  assert(found.moonlight.bytes - total < #found.parts * 4,
    "and the parts are the whole, give or take what joins them")
end

function T.sorts_the_parts_by_what_they_weigh()
  local found = result()
  for index = 2, #found.parts do
    assert(found.parts[index - 1].bytes >= found.parts[index].bytes,
      "the heaviest part comes first")
  end
end

function T.names_the_components_without_the_application_root()
  local found = result()
  local components = 0
  for _, item in ipairs(found.parts) do
    if item.kind == "component" then
      components = components + 1
      assert(not item.name:find("examples/", 1, true),
        "the root is not worth repeating: " .. item.name)
      assert(item.name:find("%.lunar$"), item.name .. " is a component")
    end
  end
  assert(components > 0, "the example app has components")
end

function T.weighs_what_the_browser_downloads()
  local found = result()
  local names = {}
  for _, item in ipairs(found.downloads) do
    names[item.name] = item
    assert(item.gzip > 0 and item.gzip < item.bytes,
      item.name .. " is smaller compressed")
  end

  assert(names["moonlight"], "the bundle is a download")
  assert(names["lua54.wasm"], "and so is the VM")
  assert(names["boot"] and names["bridge"], "and the two scripts")
  assert(names["moonlight"].bytes == found.moonlight.bytes, "it is the same bundle")
  assert(found.totals.gzip < found.totals.bytes, "the total is smaller compressed")
end

function T.leaves_the_app_without_the_pieces_it_borrowed()
  local app = lunar.app({ root = "examples/tranquility", dev = false, version = "spec" })
  local inventory = assert(bundle.inventory(app))
  assert(inventory[1].piece, "the inventory carries the bytes while it is asked for")
  assert(app.bundle_inventory == nil, "but the app does not hold them afterwards")
  assert(bundle.detailed == false, "and the next build is an ordinary one")

  assert(bundle.build(app))
  for _, item in ipairs(app.bundle_inventory) do
    assert(item.piece == nil, "an ordinary build keeps no copy of a part")
  end
end

function T.reports_without_writing_to_the_terminal()
  local lines = {}
  analyze.report(result(), function(text) lines[#lines + 1] = text end)
  local text = table.concat(lines)

  assert(text:find("what the browser downloads", 1, true))
  assert(text:find("inside moonlight", 1, true))
  assert(text:find("lua54.wasm", 1, true))
  assert(text:find("gzip alone", 1, true), "the column says what it measured")
end

return T
