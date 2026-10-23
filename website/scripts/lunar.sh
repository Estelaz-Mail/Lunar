#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
framework_dir=${LUNAR_FRAMEWORK_DIR:-$(CDPATH= cd -- "$project_root/.." && pwd)}
if [ ! -f "$framework_dir/bin/lunar" ]; then
  echo "Lunar: no framework in $framework_dir; set LUNAR_FRAMEWORK_DIR" >&2
  exit 1
fi
cd "$project_root"
if [ "${1:-}" = "package" ]; then
  export LUA_PATH="$framework_dir/?.lua;$framework_dir/?/init.lua;${LUA_PATH:-;}"
  export LUNAR_FRAMEWORK_ROOT="$framework_dir"
  exec "${LUA:-lua5.4}" scripts/build.lua "$project_root"
fi
exec "$framework_dir/bin/lunar" "$@"
