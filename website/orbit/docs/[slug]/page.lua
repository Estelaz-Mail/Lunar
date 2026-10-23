local pages = require("docs")

local function headings(body)
  local found = {}
  for anchor, text in body:gmatch('<h2 id="([^"]+)">.-</a>(.-)</h2>') do
    found[#found + 1] = { anchor = anchor, text = text }
  end
  return found
end

local function grouped()
  local groups, seen = {}, {}
  for _, item in ipairs(pages) do
    local group = seen[item.group]
    if not group then
      group = { title = item.group, links = {} }
      seen[item.group] = group
      groups[#groups + 1] = group
    end
    group.links[#group.links + 1] = { slug = item.slug, title = item.title }
  end
  return groups
end

return {
  probe = function(event)
    for index, page in ipairs(pages) do
      if page.slug == event.params.slug then
        return {
          page = page,
          groups = grouped(),
          headings = headings(page.body),
          previous = pages[index - 1],
          following = pages[index + 1],
        }
      end
    end
    event.fail(404, "Documento não encontrado")
  end,
}
