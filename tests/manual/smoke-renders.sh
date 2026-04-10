#!/usr/bin/env bash
# Real ffmpeg encode: plain flipbook via Python CLI (fixtures or generated solid PNGs).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG_DIR="${ROOT_DIR}/fixtures/images"
OUT_DIR="${ROOT_DIR}/tmp/effect-smoke"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found" >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe not found" >&2
  exit 1
fi

if [ ! -d "$IMG_DIR" ] || [ -z "$(find "$IMG_DIR" -maxdepth 1 -name '*.png' -print -quit 2>/dev/null)" ]; then
  echo "No PNG fixtures in ${IMG_DIR}; running generate-fixtures.sh..."
  bash "${ROOT_DIR}/tests/manual/generate-fixtures.sh"
fi

mkdir -p "$OUT_DIR"

probe() {
  local f="$1"
  echo "---- $(basename "$f") ----"
  ffprobe -v error -select_streams v:0 -show_entries stream=duration,nb_frames -show_entries format=size -of default=nw=1:nk=1 "$f" || true
}

echo "Plain render -> ${OUT_DIR}/flipbook-smoke.mp4"
(cd "$ROOT_DIR" && uv run slideshow live "$IMG_DIR" --render \
  --output "${OUT_DIR}/flipbook-smoke.mp4" \
  --resolution 640x360 \
  --img-per-sec 30)
probe "${OUT_DIR}/flipbook-smoke.mp4"

echo "OK: manual render smoke finished (outputs in ${OUT_DIR})"
