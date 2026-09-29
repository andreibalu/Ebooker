#!/bin/sh
# Convert an App Store capture (PNG, any iPhone size) into a site screen slot.
# Usage: sh site/tools/screen.sh <capture.png> <slot>
# Slots: home shelves recordings moment recap stats
# Writes site/src/assets/screens/<slot>.webp at 720px wide (2x for a ~360px frame).
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <capture.png> <slot>" >&2; exit 64; }
dir=$(cd "$(dirname "$0")/.." && pwd)/src/assets/screens
command -v cwebp >/dev/null || { echo "cwebp not found (brew install webp)" >&2; exit 69; }
cwebp -quiet -resize 720 0 -q 84 -m 6 -metadata none "$1" -o "$dir/$2.webp"
echo "wrote $dir/$2.webp"
