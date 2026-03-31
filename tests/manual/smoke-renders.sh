#!/usr/bin/env bash
# Real ffmpeg encodes for ken-burns (and a single crossfade) using fixtures or generated solid PNGs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG_DIR="${ROOT_DIR}/fixtures/images"
OUT_DIR="${ROOT_DIR}/tmp/effect-smoke"
SCRIPT="${ROOT_DIR}/scripts/img-effects.sh"

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

echo "Ken burns -> ${OUT_DIR}/ken-burns-smoke.mp4"
bash "$SCRIPT" ken-burns "$IMG_DIR" \
  --limit 3 --duration 0.5 --fps 24 --resolution 640x360 \
  --output "${OUT_DIR}/ken-burns-smoke.mp4"
probe "${OUT_DIR}/ken-burns-smoke.mp4"

echo "Crossfade -> ${OUT_DIR}/crossfade-smoke.mp4"
bash "$SCRIPT" crossfade "$IMG_DIR" \
  --limit 3 --duration 0.4 --fps 24 --resolution 640x360 \
  --output "${OUT_DIR}/crossfade-smoke.mp4"
probe "${OUT_DIR}/crossfade-smoke.mp4"

echo "OK: manual render smokes finished (outputs in ${OUT_DIR})"
