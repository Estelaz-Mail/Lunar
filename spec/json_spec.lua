local json = require("lunar.core.json")

local T = {}

function T.round_trips_a_document()
  local value = { name = "x", list = { 1, 2, 3 }, nested = { ok = true } }
  local decoded = assert(json.decode(json.encode(value)))
  assert(decoded.name == "x")
  assert(decoded.list[3] == 3)
  assert(decoded.nested.ok == true)
end

function T.cannot_close_the_script_it_is_embedded_in()
  local encoded = json.encode({ evil = "</script><script>alert(1)</script>" })
  assert(not encoded:find("<", 1, true))
  assert(not encoded:find(">", 1, true))
  assert(json.decode(encoded).evil == "</script><script>alert(1)</script>")
end

function T.escapes_the_line_terminators_a_json_parser_ignores()
  local encoded = json.encode({ x = "a\u{2028}b" })
  assert(encoded:find("\\u2028", 1, true))
end

function T.encodes_the_same_table_the_same_way_every_time()
  local value = { b = 1, a = 2, c = 3 }
  assert(json.encode(value) == json.encode(value))
  assert(json.encode(value) == '{"a":2,"b":1,"c":3}')
end

function T.keeps_null_apart_from_absent()
  local decoded = assert(json.decode('{"a":null}'))
  assert(decoded.a == json.null)
  assert(json.encode({ a = json.null }) == '{"a":null}')
end

function T.marks_an_empty_array_as_one()
  assert(json.encode(json.array({})) == "[]")
  assert(json.encode({ json.array({}), json.array({ 1 }) }) == "[[],[1]]")
end

function T.refuses_what_json_cannot_say()
  local ok = pcall(json.encode, { x = 0 / 0 })
  assert(not ok)
  local cycle = {}
  cycle.self = cycle
  assert(not pcall(json.encode, cycle))
end

function T.reports_where_the_input_went_wrong()
  local value, message = json.decode("{\"a\": }")
  assert(value == nil)
  assert(message:find("json:", 1, true))
  assert(json.decode("[1,2") == nil)
  assert(json.decode('{"a":1} trailing') == nil)
end

function T.decodes_escapes_and_surrogate_pairs()
  assert(json.decode('"\\u0041"') == "A")
  assert(json.decode('"\\ud83d\\ude00"') == "\u{1f600}")
  assert(json.decode('"a\\nb"') == "a\nb")
end

return T
