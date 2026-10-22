local fs = require("lunar.core.fs")
local lunar = require("lunar")
local manifest = require("lunar.site.manifest")
local util = require("lunar.core.util")

local T = {}

local PAGE = [[
<script>
  props { data = {} }
</script>
<h1>home</h1>
]]

local function temp_app(declared, files)
  local root = fs.join(os.getenv("TMPDIR") or "/tmp",
    string.format("lunar-manifest-%d-%d", os.time(), math.random(100000)))
  fs.mkdirp(fs.join(root, "orbit"))
  assert(util.write_file(fs.join(root, "orbit/page.lunar"), PAGE))
  for relative, source in pairs(files or {}) do
    local path = fs.join(root, relative)
    fs.mkdirp(fs.dirname(path))
    assert(util.write_file(path, source))
  end
  if declared then
    assert(util.write_file(fs.join(root, manifest.FILE), declared))
  end
  return root
end

local function clean(root)
  os.execute("rm -rf " .. root)
end

function T.reads_what_the_app_would_otherwise_be_told()
  local root = temp_app([[
{
  "name": "Tranquility",
  "version": "2.1.0",
  "lang": "pt-BR",
  "client": false,
  "minify": false,
  "host": "127.0.0.1",
  "port": 4000,
  "stylesheets": ["/css/app.css"],
  "description": "ignored, but allowed"
}
]])
  local instance = lunar.app({ root = root })

  assert(instance.name == "Tranquility")
  assert(instance.version == "2.1.0")
  assert(instance.lang == "pt-BR")
  assert(instance.client == false)
  assert(instance.minify == false)
  assert(instance.stylesheets[1] == "/css/app.css")

  local host, port = lunar.listen_options(instance, {})
  assert(host == "127.0.0.1", host)
  assert(port == 4000, port)
  clean(root)
end

function T.what_the_caller_says_beats_the_manifest()
  local root = temp_app('{ "name": "From the file", "port": 4000, "lang": "pt-BR" }')
  local instance = lunar.app({ root = root, name = "From the call", lang = "en" })

  assert(instance.name == "From the call")
  assert(instance.lang == "en")

  local host, port = lunar.listen_options(instance, { host = "0.0.0.0", port = 8080 })
  assert(host == "0.0.0.0")
  assert(port == 8080)
  clean(root)
end

function T.an_app_without_one_is_an_app_with_defaults()
  local root = temp_app(nil)
  local instance = lunar.app({ root = root })

  assert(instance.name == fs.basename(root))
  assert(instance.lang == "en")
  assert(instance.client == true)
  local host, port = lunar.listen_options(instance, { default_host = "127.0.0.1" })
  assert(host == "127.0.0.1")
  assert(port == 3000)
  clean(root)
end

function T.says_which_field_is_wrong()
  local root = temp_app('{ "port": "3000" }')
  local ok, err = pcall(lunar.app, { root = root })
  assert(ok == false, "a string port was accepted")
  assert(tostring(err):find("port must be a number", 1, true), tostring(err))
  clean(root)

  root = temp_app('{ "port": 70000 }')
  local _, out_of_range = pcall(lunar.app, { root = root })
  assert(tostring(out_of_range):find("between 1 and 65535", 1, true), tostring(out_of_range))
  clean(root)

  root = temp_app('{ "stylesheets": [1] }')
  local _, bad_list = pcall(lunar.app, { root = root })
  assert(tostring(bad_list):find("stylesheets[1] must be a string", 1, true), tostring(bad_list))
  clean(root)
end

function T.says_when_a_key_is_not_a_thing_it_reads()
  local root = temp_app('{ "clientt": true }')
  local ok, err = pcall(lunar.app, { root = root })
  assert(ok == false, "a typo was accepted")
  assert(tostring(err):find("clientt is not something Lunar reads", 1, true), tostring(err))
  clean(root)
end

function T.says_when_the_json_is_not_json()
  local root = temp_app('{ "name": }')
  local ok, err = pcall(lunar.app, { root = root })
  assert(ok == false, "broken JSON was accepted")
  assert(tostring(err):find(manifest.FILE, 1, true), tostring(err))
  clean(root)
end

function T.the_manifest_is_watched_like_everything_else()
  local root = temp_app('{ "name": "First" }')
  local instance = lunar.app({ root = root, dev = true, watch_interval = 0 })
  assert(instance.name == "First")
  assert(instance.watcher ~= nil)

  local first = instance:generation()
  instance:refresh(true)
  assert(util.write_file(fs.join(root, manifest.FILE), '{ "name": "Second" }'))
  instance:refresh(true)
  assert(instance:generation() > first, "editing the manifest moves the generation")
  clean(root)
end

return T
