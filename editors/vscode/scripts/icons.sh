#!/bin/sh
# Regenerates the extension's icons from the project's logo.
#
# The PNGs are checked in, because the manifest points at them and this
# extension has no build step. This script exists so `Logo Lunar.png` in the
# repository root stays the one source of the artwork: it crops the mark out
# of it (the wordmark underneath is dropped, which is what an icon wants),
# squares it off and writes the two sizes VS Code asks for.
#
#   sh scripts/icons.sh      # needs ImageMagick
set -e
cd "$(dirname "$0")/.."
logo="../../Logo Lunar - Fundo Preto.png"

# The mark ends where the wordmark begins, at about y=1160 of 1652.
convert "$logo" -crop 1546x1160+0+0 +repage \
	-background black -gravity center -extent 1546x1546 \
	-resize 256x256 images/icon.png

convert images/icon.png -resize 32x32 images/lunar-file.png

echo "wrote images/icon.png and images/lunar-file.png from $logo"
