local here = arg[0]:match("^(.*[/\\])") or "./"
package.path = here .. "../lib/?.lua;" .. package.path
local markdown = require("markdown")

local ORDER = {
    "introducao",
    "instalacao",
    "componentes",
    "template",
    "reatividade",
    "rotas",
    "dados",
    "renderizacao",
    "wasm",
    "seguranca",
    "workers",
    "cli",
}

local function quote(s)
    return string.format("%q", s)
end

local chunks = { "return {\n" }
for _, slug in ipairs(ORDER) do
    local f = assert(io.open("docs/" .. slug .. ".md", "rb"))
    local src = f:read("*a")
    f:close()
    local meta, body = markdown.parse(src)
    chunks[#chunks + 1] = "  {\n"
    chunks[#chunks + 1] = "    slug = " .. quote(meta.slug or slug) .. ",\n"
    chunks[#chunks + 1] = "    group = " .. quote(meta.group) .. ",\n"
    chunks[#chunks + 1] = "    title = " .. quote(meta.title) .. ",\n"
    chunks[#chunks + 1] = "    description = " .. quote(meta.description) .. ",\n"
    chunks[#chunks + 1] = "    source = [====[\n" .. body .. "]====],\n"
    chunks[#chunks + 1] = "  },\n"
end
chunks[#chunks + 1] = "}\n"

local out = assert(io.open("lib/docs_catalog.lua", "wb"))
out:write(table.concat(chunks))
out:close()
print("wrote lib/docs_catalog.lua")
