local M = {}

local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function inline(s)
    local holes = {}
    local function keep(html)
        holes[#holes + 1] = html
        return "\1" .. #holes .. "\2"
    end
    s = s:gsub("`` (.-) ``", function(code)
        return keep("<code>" .. esc(code) .. "</code>")
    end)
    s = s:gsub("`([^`]+)`", function(code)
        return keep("<code>" .. esc(code) .. "</code>")
    end)
    s = s:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(text, href)
        return keep('<a href="' .. esc(href) .. '">' .. inline(text) .. "</a>")
    end)
    s = esc(s)
    s = s:gsub("\1(%d+)\2", function(i)
        return holes[tonumber(i)]
    end)
    return s
end

local function slugify(text)
    local map = {
        ["á"] = "a", ["à"] = "a", ["ã"] = "a", ["â"] = "a",
        ["é"] = "e", ["ê"] = "e",
        ["í"] = "i",
        ["ó"] = "o", ["ô"] = "o", ["õ"] = "o",
        ["ú"] = "u",
        ["ç"] = "c",
    }
    text = text:lower()
    text = text:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch)
        return map[ch] or ch
    end)
    text = text:gsub("[^%w%s%-]", "")
    text = text:gsub("%s+", "-")
    text = text:gsub("%-+", "-")
    return text
end

local function heading(level, line)
    local title, id = line:match("^(.-)%s+{#([%w%-]+)}%s*$")
    if not title then
        title = line
        id = slugify(title)
    end
    title = title:gsub("^#+%s*", "")
    local html_title = inline(title)
    if level == 2 then
        return '<h2 id="' .. id .. '"><a class="doc-anchor" href="#' .. id .. '" aria-label="Link para esta seção">#</a>' .. html_title .. "</h2>"
    end
    return "<h3>" .. html_title .. "</h3>"
end

local function fence(info, body)
    local cap = info ~= "" and info or nil
    local code = esc(body)
    if cap then
        return '<figure class="doc-code"><figcaption>' .. esc(cap) .. "</figcaption><pre><code>" .. code .. "</code></pre></figure>"
    end
    return '<figure class="doc-code"><pre><code>' .. code .. "</code></pre></figure>"
end

local function table_html(lines)
    local rows = {}
    for _, line in ipairs(lines) do
        if not line:match("^|%s*%-") then
            local cells = {}
            local inner = line:gsub("^|", ""):gsub("|$", "")
            for cell in (inner .. "|"):gmatch("(.-)|") do
                cells[#cells + 1] = inline((cell:gsub("^%s+", ""):gsub("%s+$", "")))
            end
            rows[#rows + 1] = cells
        end
    end
    if #rows == 0 then
        return ""
    end
    local html = { '<div class="doc-table"><table><thead><tr>' }
    for _, cell in ipairs(rows[1]) do
        html[#html + 1] = "<th>" .. cell .. "</th>"
    end
    html[#html + 1] = "</tr></thead><tbody>"
    for i = 2, #rows do
        html[#html + 1] = "<tr>"
        for _, cell in ipairs(rows[i]) do
            html[#html + 1] = "<td>" .. cell .. "</td>"
        end
        html[#html + 1] = "</tr>"
    end
    html[#html + 1] = "</tbody></table></div>"
    return table.concat(html)
end

function M.render(src)
    src = src:gsub("\r\n", "\n")
    if src:sub(-1) ~= "\n" then
        src = src .. "\n"
    end
    local out = {}
    local para = {}
    local i = 1
    local lines = {}
    for line in src:gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    local function emit_para()
        if #para > 0 then
            out[#out + 1] = "<p>" .. inline(table.concat(para, " ")) .. "</p>"
            para = {}
        end
    end
    while i <= #lines do
        local line = lines[i]
        if line:match("^```") then
            emit_para()
            local info = line:match("^```(.*)$") or ""
            local body = {}
            i = i + 1
            while i <= #lines and not lines[i]:match("^```%s*$") do
                body[#body + 1] = lines[i]
                i = i + 1
            end
            out[#out + 1] = fence(info, table.concat(body, "\n"))
        elseif line == ":::note" or line == ":::warn" then
            emit_para()
            local kind = line == ":::warn" and "doc-note warn" or "doc-note"
            local body = {}
            i = i + 1
            while i <= #lines and lines[i] ~= ":::" do
                body[#body + 1] = lines[i]
                i = i + 1
            end
            out[#out + 1] = '<div class="' .. kind .. '">' .. inline(table.concat(body, " ")) .. "</div>"
        elseif line:match("^|") then
            emit_para()
            local block = {}
            while i <= #lines and lines[i]:match("^|") do
                block[#block + 1] = lines[i]
                i = i + 1
            end
            out[#out + 1] = table_html(block)
            i = i - 1
        elseif line:match("^## ") then
            emit_para()
            out[#out + 1] = heading(2, line)
        elseif line:match("^### ") then
            emit_para()
            out[#out + 1] = heading(3, line)
        elseif line:match("^%- ") then
            emit_para()
            local items = {}
            while i <= #lines and lines[i]:match("^%- ") do
                items[#items + 1] = "<li>" .. inline(lines[i]:sub(3)) .. "</li>"
                i = i + 1
            end
            out[#out + 1] = "<ul>" .. table.concat(items) .. "</ul>"
            i = i - 1
        elseif line:match("^%s*$") then
            emit_para()
        else
            para[#para + 1] = line
        end
        i = i + 1
    end
    emit_para()
    return table.concat(out)
end

function M.parse(src)
    src = src:gsub("\r\n", "\n")
    if src:sub(1, 4) ~= "---\n" then
        error("missing front matter")
    end
    local close = src:find("\n---\n", 5, true)
    if not close then
        error("unclosed front matter")
    end
    local fm = src:sub(5, close - 1)
    local body = src:sub(close + 5)
    local meta = {}
    for line in (fm .. "\n"):gmatch("(.-)\n") do
        local key, value = line:match("^([%w_]+):%s*(.*)$")
        if key then
            if value:match("^\".*\"$") then
                value = value:sub(2, -2):gsub('\\"', '"')
            end
            meta[key] = value
        end
    end
    return meta, body
end

return M
