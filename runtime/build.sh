#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bun "$project/runtime/prepare.ts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
version=5.4.9
digest=2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6
curl --proto '=https' --tlsv1.2 -fsSL "https://www.lua.org/ftp/lua-$version.tar.gz" -o "$work/lua.tar.gz"
actual=$(sha256sum "$work/lua.tar.gz" | cut -d' ' -f1)
[ "$actual" = "$digest" ] || { echo 'Lua source checksum mismatch' >&2; exit 1; }
tar xzf "$work/lua.tar.gz" -C "$work"
source_dir=$work/lua-$version/src
set --
for source in "$source_dir"/*.c; do
  case "$source" in */lua.c|*/luac.c) continue ;; esac
  set -- "$@" "$source"
done
"${EMCC:-emcc}" -Oz -flto -I"$source_dir" "$project/runtime/bridge.c" "$@" \
  --no-entry -sSTANDALONE_WASM=1 -sFILESYSTEM=0 -sALLOW_MEMORY_GROWTH=1 \
  -sINITIAL_MEMORY=2097152 -sSTACK_SIZE=262144 -sSUPPORT_LONGJMP=wasm \
  -sMALLOC=emmalloc -o "$project/static/runtime/lua54.wasm"
