local compress = require("lunar.http.compress")
local gzip = require("lunar.core.gzip")
local request = require("lunar.http.request")
local response = require("lunar.http.response")

local T = {}

local function req(headers)
  local all = headers or {}
  all.host = "localhost"
  return request.new({ method = "GET", target = "/", headers = all }, {})
end

local function unpacked(packed)
  local path = os.tmpname()
  local handle = assert(io.open(path, "wb"))
  handle:write(packed)
  handle:close()
  local pipe = assert(io.popen("gzip -dc " .. path .. " 2>/dev/null"))
  local text = pipe:read("*a")
  pipe:close()
  os.remove(path)
  return text
end

local PAGE = string.rep("<p>a paragraph of ordinary prose</p>\n", 200)

function T.a_gzip_stream_survives_a_round_trip()
  for _, sample in ipairs({
    "",
    "a",
    string.rep("x", 70000),
    PAGE,
    ("\0\1\2\255"):rep(500),
  }) do
    assert(unpacked(gzip.compress(sample)) == sample,
      "a sample of " .. #sample .. " bytes came back changed")
  end
end

function T.the_stream_carries_the_length_and_the_checksum()
  local packed = gzip.compress(PAGE)
  assert(packed:sub(1, 3) == "\31\139\8", "it starts with the gzip magic")
  local crc, size = string.unpack("<I4I4", packed, #packed - 7)
  assert(size == #PAGE, "the trailer carries the original length")
  assert(crc == gzip.crc32(PAGE), "and its checksum")
end

function T.it_compresses_a_page_for_a_client_that_asked()
  local res = response.html(PAGE)
  local out = compress.response(req({ ["accept-encoding"] = "gzip, deflate" }), res)

  assert(out.headers["Content-Encoding"] == "gzip", "it says what it did")
  assert(#out.body < #PAGE, "and the body is smaller")
  assert(unpacked(out.body) == PAGE, "and it is the same page")
end

function T.it_leaves_a_client_that_did_not_ask_alone()
  local out = compress.response(req({}), response.html(PAGE))
  assert(out.headers["Content-Encoding"] == nil, "nothing was encoded")
  assert(out.body == PAGE)
  assert(out.headers["Vary"] == "Accept-Encoding", "but the answer still varies")
end

function T.it_refuses_an_encoding_the_client_turned_off()
  local out = compress.response(req({ ["accept-encoding"] = "gzip;q=0" }),
    response.html(PAGE))
  assert(out.headers["Content-Encoding"] == nil, "q=0 is a refusal")
end

function T.it_adds_itself_to_a_vary_that_was_already_there()
  local res = response.html(PAGE, 200, { ["Vary"] = "Accept" })
  local out = compress.response(req({ ["accept-encoding"] = "gzip" }), res)
  assert(out.headers["Vary"] == "Accept, Accept-Encoding",
    "a cache must key on both, not on " .. tostring(out.headers["Vary"]))

  assert(compress.vary("Accept-Encoding") == "Accept-Encoding", "and it says it once")
  assert(compress.vary("accept, accept-encoding") == "accept, accept-encoding")
  assert(compress.vary("*") == "*")
end

function T.it_leaves_short_bodies_and_binary_alone()
  local short = compress.response(req({ ["accept-encoding"] = "gzip" }),
    response.html("<p>hi</p>"))
  assert(short.headers["Content-Encoding"] == nil, "a small page is not worth it")

  local image = response.new(200, string.rep("\137PNG", 2000),
    { ["Content-Type"] = "image/png" })
  local out = compress.response(req({ ["accept-encoding"] = "gzip" }), image)
  assert(out.headers["Content-Encoding"] == nil, "an image is already compressed")
end

function T.it_does_not_encode_twice()
  local res = response.new(200, PAGE, {
    ["Content-Type"] = "text/html; charset=utf-8",
    ["Content-Encoding"] = "br",
  })
  local out = compress.response(req({ ["accept-encoding"] = "gzip" }), res)
  assert(out.headers["Content-Encoding"] == "br", "what was encoded stays encoded")
  assert(out.body == PAGE)
end

function T.it_keeps_the_framing_headers_honest()
  local res = response.html(PAGE, 200, { ["Content-Length"] = tostring(#PAGE),
    ["ETag"] = '"abc"' })
  local out = compress.response(req({ ["accept-encoding"] = "gzip" }), res)
  assert(tonumber(out.headers["Content-Length"]) == #out.body,
    "the length is the length of what was sent")
  assert(out.headers["ETag"] == '"abc-gzip"', "and the tag names the encoding")
end

function T.it_leaves_a_stream_and_a_file_response_alone()
  local streamed = response.html("")
  streamed.stream = function() end
  assert(compress.response(req({ ["accept-encoding"] = "gzip" }), streamed).body == "")

  local sent = response.html("")
  sent.file = { path = "/dev/null", length = 0, offset = 0 }
  local out = compress.response(req({ ["accept-encoding"] = "gzip" }), sent)
  assert(out.headers["Content-Encoding"] == nil, "a file is served by the file path")
end


function T.colliding_short_hashes_never_reuse_another_responses_body()
  local first = string.rep("x", 2048) .. "AM8fZVTCAbQT"
  local second = string.rep("x", 2048) .. "DXJaMnFd0el4"
  assert(first ~= second and #first == #second)
  local util = require("lunar.core.util")
  assert(util.hash(first) == util.hash(second), "the regression fixture collides")
  compress.forget()
  assert(unpacked(compress.gzip(first)) == first)
  assert(unpacked(compress.gzip(second)) == second)
  assert(unpacked(compress.gzip(first)) == first)
end

return T
