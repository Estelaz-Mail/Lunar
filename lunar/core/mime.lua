local mime = {}

local TYPES = {
  avif = "image/avif", bmp = "image/bmp", css = "text/css; charset=utf-8",
  csv = "text/csv; charset=utf-8", gif = "image/gif", gz = "application/gzip",
  htm = "text/html; charset=utf-8", html = "text/html; charset=utf-8",
  ico = "image/x-icon", jpeg = "image/jpeg", jpg = "image/jpeg",
  js = "text/javascript; charset=utf-8", json = "application/json; charset=utf-8",
  lua = "text/x-lua; charset=utf-8", m4a = "audio/mp4", map = "application/json",
  md = "text/markdown; charset=utf-8", mjs = "text/javascript; charset=utf-8",
  mp3 = "audio/mpeg", mp4 = "video/mp4", otf = "font/otf", pdf = "application/pdf",
  png = "image/png", svg = "image/svg+xml", txt = "text/plain; charset=utf-8",
  ttf = "font/ttf", wasm = "application/wasm", wav = "audio/wav",
  webm = "video/webm", webp = "image/webp", woff = "font/woff", woff2 = "font/woff2",
  xml = "application/xml", zip = "application/zip",
}

function mime.of(path)
  local extension = path:match("%.([%w]+)$")
  if not extension then return "application/octet-stream" end
  return TYPES[extension:lower()] or "application/octet-stream"
end

mime.TYPES = TYPES

return mime
