local compiler = require("lunar.compiler")
local formatter = require("lunar.compiler.format")
local component = require("lunar.runtime.component")
local mockdom = require("mockdom")

local T = {}

local function framework_component(name)
  local cache = compiler.cache({ root = "spec/fixtures", framework = "." })
  local def, err = cache:resolve("lunar/ui/" .. name, "spec/fixtures/App.lunar")
  assert(def, err)
  return def
end

function T.resolves_the_lunar_ui_library_from_the_framework()
  local button = framework_component("Button")
  local markup = component.render(button, { label = "Salvar", variant = "primary" })
  assert(markup:find("Salvar", 1, true))
  assert(markup:find("lunar%-button", 1))
  assert(markup:find("lunar%-button%-primary", 1))
end

function T.renders_ui_components_with_server_and_browser_markup_in_agreement()
  local card = framework_component("Card")
  local markup = component.render(card, { title = "Conta" })
  local dom = mockdom.new()
  component.mount(card, dom.body, { title = "Conta" }, { dom = dom })
  assert(markup:find("Conta", 1, true))
end

function T.renders_the_icons_used_by_the_estelaz_public_home()
  local icon = framework_component("Icon")
  for _, name in ipairs({ "shield", "cloud", "rocket", "headset", "mobile", "lock" }) do
    local markup = component.render(icon, { name = name })
    assert(markup:find("<path", 1, true) or markup:find("<rect", 1, true), name)
  end
  local shield = component.render(icon, { name = "shield" })
  assert(shield:find('viewBox="0 0 512 512"', 1, true))
end

function T.compiles_every_first_wave_ui_component()
  for _, name in ipairs({ "Button", "Card", "Stack", "Badge", "Alert", "Field", "Spinner", "Icon" }) do
    assert(framework_component(name), name .. " did not compile")
  end
end

function T.compiles_the_second_wave_ui_components()
  for _, name in ipairs({ "Checkbox", "Switch", "Select", "Textarea", "Progress", "Skeleton", "Modal", "Drawer", "Tabs", "Tooltip", "Table", "Toast", "Menu", "Radio", "Pagination", "Container", "Divider" }) do
    assert(framework_component(name), name .. " did not compile")
  end
end

function T.renders_feedback_and_overlay_components_only_when_active()
  local modal = framework_component("Modal")
  local toast = framework_component("Toast")
  local closed = component.render(modal, { open = false, title = "Confirmar" })
  local visible = component.render(modal, { open = true, title = "Confirmar" })
  local hidden_toast = component.render(toast, { visible = false, message = "Pronto" })
  local visible_toast = component.render(toast, { visible = true, message = "Pronto" })
  assert(not closed:find('role="dialog"', 1, true))
  assert(visible:find('role="dialog"', 1, true))
  assert(not hidden_toast:find("Pronto", 1, true))
  assert(visible_toast:find("Pronto", 1, true))
end

function T.formats_lunar_sources_without_external_formatters()
  local source = "<div>\n<span>Lua</span>\n</div>\n"
  local formatted = formatter.format(source)
  assert(formatted == "<div>\n  <span>Lua</span>\n</div>\n")
  assert(formatter.format(formatted) == formatted)
end

return T
