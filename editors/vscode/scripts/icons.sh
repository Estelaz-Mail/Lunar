#!/bin/sh
set -e
cd "$(dirname "$0")/.."
cp ../../brand/icon.png images/icon.png
cp ../../brand/favicon.png images/lunar-file.png
echo "copied images/icon.png and images/lunar-file.png from brand/"
