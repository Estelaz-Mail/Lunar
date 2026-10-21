local util = require("lunar.core.util")

local T = {}

function T.splits_on_a_separator()
  assert(table.concat(util.split("a/b/c", "/"), "|") == "a|b|c")
  -- An empty string has no segments, which is what the route splitter wants.
  assert(#util.split("", "/") == 0)
  assert(table.concat(util.split("a//b", "/"), "|") == "a||b")
  -- A trailing separator adds no empty segment, so `/a/b/` and `/a/b` are the
  -- same path to the router.
  assert(table.concat(util.split("a/b/", "/"), "|") == "a|b")
  assert(table.concat(util.split("/a", "/"), "|") == "|a")
end

function T.escapes_a_pattern_so_a_literal_stays_literal()
  assert(("a.b"):match("^" .. util.pattern_escape("a.b") .. "$"))
  assert(not ("axb"):match("^" .. util.pattern_escape("a.b") .. "$"))
end

function T.counts_the_lines_the_compiler_has_to_keep()
  assert(util.count_lines("") == 1)
  assert(util.count_lines("a\nb") == 2)
  assert(util.count_lines("a\n") == 2)
end

function T.hashes_the_same_input_to_the_same_class()
  assert(util.hash("abc") == util.hash("abc"))
  assert(util.hash("abc") ~= util.hash("abd"))
  assert(#util.hash("abc") == 8)
end

function T.merges_left_to_right()
  local merged = util.merge({ a = 1, b = 2 }, nil, { b = 3 })
  assert(merged.a == 1 and merged.b == 3)
end

return T
