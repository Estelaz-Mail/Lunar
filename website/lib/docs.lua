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

local function read_file(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end
    local src = f:read("*a")
    f:close()
    return src
end

local function load_catalog()
    local ok, catalog = pcall(require, "docs_catalog")
    if ok then
        return catalog
    end
    local pages = {}
    for _, slug in ipairs(ORDER) do
        local src = assert(read_file("docs/" .. slug .. ".md"), "missing docs/" .. slug .. ".md")
        local meta, body = markdown.parse(src)
        pages[#pages + 1] = {
            slug = meta.slug or slug,
            group = meta.group,
            title = meta.title,
            description = meta.description,
            source = body,
        }
    end
    return pages
end

local pages = {}
for _, item in ipairs(load_catalog()) do
    pages[#pages + 1] = {
        slug = item.slug,
        group = item.group,
        title = item.title,
        description = item.description,
        body = markdown.render(item.source),
    }
end

return pages
