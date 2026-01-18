#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/images-to-video.sh <images_dir> [img_per_sec] [resolution] [output]
# Example: scripts/images-to-video.sh ~/cool-pics 60 1920x1080 out.mp4

DIR="${1:-.}"
IPS="${2:-60}"              # images per second
RES="${3:-1920x1080}"
OUT="${4:-flipbook.mp4}"

# Expand tilde if present
DIR="${DIR/#\~/$HOME}"

# Find images and create sorted list
TMPLIST="$(mktemp)"
find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$TMPLIST"

if [ ! -s "$TMPLIST" ]; then
  echo "Error: No images found in $DIR" >&2
  rm -f "$TMPLIST"
  exit 1
fi

COUNT=$(wc -l < "$TMPLIST")
echo "Found $COUNT images"
echo "Creating video: $OUT (${IPS} images/sec, ${RES})"

# Build concat list for stable ordering
CONCAT="$(mktemp)"
while IFS= read -r f; do
  printf "file '%s'\n" "$f" >> "$CONCAT"
done < "$TMPLIST"

# Create video using Apple VideoToolbox HEVC
if ! ffmpeg -f concat -safe 0 -i "$CONCAT" \
  -r "$IPS" \
  -vf "scale=${RES}:flags=lanczos,fps=${IPS}" \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -b:v 25M \
  -maxrate 55M \
  -bufsize 100M \
  -pix_fmt yuv420p \
  -an \
  -y "$OUT" 2>/dev/null; then
  echo "Error: Failed to create video" >&2
  rm -f "$TMPLIST" "$CONCAT"
  exit 1
fi

rm -f "$TMPLIST" "$CONCAT"
echo "✓ Video created: $OUT"
echo "Play with: mpv --fs \"$OUT\""
