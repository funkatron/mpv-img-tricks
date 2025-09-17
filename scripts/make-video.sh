#!/usr/bin/env bash
set -euo pipefail
# Usage: scripts/make-video.sh <images_dir> <img_per_sec> <w>x<h> <out.mp4>
# Ex:    scripts/make-video.sh ~/cool-pics 60 1920x1080 out.mp4
DIR="${1:-.}"
IPS="${2:-60}"              # images per second (each image duration = 1/IPS)
RES="${3:-1920x1080}"
OUT="${4:-flipbook.mp4}"

# Sort filenames naturally; fall back to glob order if 'ls -v' unsupported.
# If you need recursive, replace with: find "$DIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) | sort -V
TMPLIST="$(mktemp)"
ls -v "$DIR"/*.{jpg,JPG,jpeg,JPEG,png,PNG,webp,WEBP} 2>/dev/null | sed '/^\s*$/d' > "$TMPLIST"

if [ ! -s "$TMPLIST" ]; then
  echo "No images found in $DIR"
  rm -f "$TMPLIST"
  exit 1
fi

# Build a concat list for stable ordering and exact frame pacing:
# We will map each image to exactly 1 frame at IPS fps by duplicating frames via the fps filter.
# Simpler approach: use image2 demuxer with -framerate $IPS, but concat + fps tends to be robust w/ mixed formats.
# Note: For very large sets, image2 with -framerate may be faster. See alt path below.
CONCAT="$(mktemp)"
while IFS= read -r f; do
  printf "file '%s'\n" "$f" >> "$CONCAT"
  # duration isn't used here; timing controlled by -framerate/fps downstream
done < "$TMPLIST"

# Encode using Apple VideoToolbox HEVC and tag hvc1 for QuickTime compatibility on macOS
# If you prefer H.264, replace hevc_videotoolbox with h264_videotoolbox and drop -tag:v.
ffmpeg -f concat -safe 0 -i "$CONCAT" \
  -r "$IPS" \
  -vf "scale=${RES}:flags=lanczos,fps=${IPS}" \
  -c:v hevc_videotoolbox -tag:v hvc1 -b:v 25M -maxrate 55M -bufsize 100M \
  -pix_fmt yuv420p \
  -an \
  -y "$OUT"

rm -f "$TMPLIST" "$CONCAT"
echo "Wrote: $OUT"
echo "Play with: mpv --fs \"$OUT\""
