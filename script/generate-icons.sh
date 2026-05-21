#!/bin/bash
set -e

ICON_SRC="/Users/grillermo/c/readitsoon/public/icon.svg"
OUT_DIR="$(dirname "$0")/../assets"
mkdir -p "$OUT_DIR"

# Make all fills white
sed 's/fill="#[a-fA-F0-9]\{6\}"/fill="#FFFFFF"/g' "$ICON_SRC" > "$OUT_DIR/icon-white.svg"

# Render at menu bar sizes
rsvg-convert -w 22 -h 22 "$OUT_DIR/icon-white.svg" > "$OUT_DIR/icon-22.png"
rsvg-convert -w 44 -h 44 "$OUT_DIR/icon-white.svg" > "$OUT_DIR/icon-44.png"

echo "Icons generated in $OUT_DIR"
echo "icons.go uses //go:embed assets/icon-22.png"
