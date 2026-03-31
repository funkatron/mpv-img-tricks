#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG_DIR="${ROOT_DIR}/fixtures/images"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found; install it to generate fixtures." >&2
  exit 1
fi

mkdir -p "$IMG_DIR"

make_tile() {
  local color="$1"
  local out="$2"
  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=${color}:s=320x240:d=1" -frames:v 1 "$out"
}

make_tile "0xcc3333" "${IMG_DIR}/tile-a.png"
make_tile "0x33aa66" "${IMG_DIR}/tile-b.png"
make_tile "0x3355cc" "${IMG_DIR}/tile-c.png"
make_tile "0xaa8833" "${IMG_DIR}/tile-d.png"

echo "Wrote PNG fixtures under fixtures/images/"
