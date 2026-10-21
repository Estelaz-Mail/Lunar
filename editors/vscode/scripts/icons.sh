#!/bin/sh
# Copies the extension's icons out of the project's brand directory.
#
# The PNGs are checked in, because the manifest points at them and this
# extension has no build step; this script exists so that `brand/` stays the
# one place the artwork lives. Run `python3 brand/make.py` first if the logo
# itself has changed.
#
#   sh scripts/icons.sh
set -e
cd "$(dirname "$0")/.."
cp ../../brand/icon.png images/icon.png
cp ../../brand/favicon.png images/lunar-file.png
echo "copied images/icon.png and images/lunar-file.png from brand/"
