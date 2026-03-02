#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/img-effects.sh"

fail() {
  echo "TEST FAILED: $1"
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! rg -F --quiet -- "$pattern" "$file"; then
    echo "Expected pattern not found: $pattern"
    echo "---- $file ----"
    sed -n '1,120p' "$file" || true
    fail "missing expected pattern"
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if rg -F --quiet -- "$pattern" "$file"; then
    echo "Unexpected pattern found: $pattern"
    echo "---- $file ----"
    sed -n '1,120p' "$file" || true
    fail "found unexpected pattern"
  fi
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BIN_DIR="${WORK_DIR}/bin"
MEDIA_DIR="${WORK_DIR}/media"
mkdir -p "$BIN_DIR" "$MEDIA_DIR"

touch "${MEDIA_DIR}/a.mov" "${MEDIA_DIR}/b.mov"

FFMPEG_LOG="${WORK_DIR}/ffmpeg.log"
MPV_LOG="${WORK_DIR}/mpv.log"
export FFMPEG_LOG MPV_LOG

cat > "${BIN_DIR}/ffprobe" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${BIN_DIR}/system_profiler" <<'EOF'
#!/usr/bin/env bash
echo "Resolution: 1920 x 1080"
EOF

cat > "${BIN_DIR}/ffmpeg" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -ge 2 ] && [ "$1" = "-hide_banner" ] && [ "$2" = "-encoders" ]; then
  echo " V..... hevc_videotoolbox           VideoToolbox H.265 Encoder"
  echo " V..... libx264                     H.264 / AVC / MPEG-4 AVC"
  exit 0
fi
printf '%s\n' "$*" >> "$FFMPEG_LOG"
out_file="${!#}"
mkdir -p "$(dirname "$out_file")"
touch "$out_file"
exit 0
EOF

cat > "${BIN_DIR}/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MPV_LOG"
exit 0
EOF

chmod +x "${BIN_DIR}/ffprobe" "${BIN_DIR}/system_profiler" "${BIN_DIR}/ffmpeg" "${BIN_DIR}/mpv"

export PATH="${BIN_DIR}:$PATH"

# Animated mode should emit video composites and ffmpeg video segment args.
bash "$SCRIPT_PATH" tile "${MEDIA_DIR}/*.mov" \
  --randomize --group-size 2 --max-files 2 \
  --duration 0.2 --fps 12 --animate-videos --no-cache >/dev/null

assert_contains "$FFMPEG_LOG" "-t 0.2"
assert_contains "$FFMPEG_LOG" "-c:v hevc_videotoolbox"
assert_not_contains "$FFMPEG_LOG" "-frames:v 1"
assert_contains "$MPV_LOG" ".mp4"

: > "$FFMPEG_LOG"
: > "$MPV_LOG"

# Forced encoder should honor explicit override when available.
bash "$SCRIPT_PATH" tile "${MEDIA_DIR}/*.mov" \
  --randomize --group-size 2 --max-files 2 \
  --duration 0.2 --fps 12 --animate-videos --encoder libx264 --no-cache >/dev/null

assert_contains "$FFMPEG_LOG" "-c:v libx264"
assert_not_contains "$FFMPEG_LOG" "-c:v hevc_videotoolbox"

: > "$FFMPEG_LOG"
: > "$MPV_LOG"

# Default mode should emit still composites and frame-grab args.
bash "$SCRIPT_PATH" tile "${MEDIA_DIR}/*.mov" \
  --randomize --group-size 2 --max-files 2 \
  --duration 0.2 --fps 12 --no-cache >/dev/null

assert_contains "$FFMPEG_LOG" "-frames:v 1"
assert_not_contains "$FFMPEG_LOG" "-t 0.2"
assert_contains "$MPV_LOG" ".jpg"

echo "PASS: img-effects tile animation switch"
