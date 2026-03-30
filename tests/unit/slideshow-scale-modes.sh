#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPELINE_SCRIPT="${ROOT_DIR}/scripts/mpv-pipeline.sh"
SLIDESHOW_SCRIPT="${ROOT_DIR}/scripts/slideshow.sh"

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

touch "${MEDIA_DIR}/a.jpg" "${MEDIA_DIR}/b.jpg"
PLAYLIST="${WORK_DIR}/playlist.m3u"
printf "%s\n" "${MEDIA_DIR}/a.jpg" > "$PLAYLIST"

MPV_LOG="${WORK_DIR}/mpv.log"
export MPV_LOG

cat > "${BIN_DIR}/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MPV_LOG"
exit 0
EOF
chmod +x "${BIN_DIR}/mpv"
export PATH="${BIN_DIR}:$PATH"

# Pipeline scale mapping checks.
bash "$PIPELINE_SCRIPT" --playlist "$PLAYLIST" --scale-mode fit --fullscreen no --loop-mode none --no-audio yes >/dev/null
assert_contains "$MPV_LOG" "--keepaspect"
assert_contains "$MPV_LOG" "--panscan=0.0"
assert_not_contains "$MPV_LOG" "--no-keepaspect"

: > "$MPV_LOG"
bash "$PIPELINE_SCRIPT" --playlist "$PLAYLIST" --scale-mode fill --fullscreen no --loop-mode none --no-audio yes >/dev/null
assert_contains "$MPV_LOG" "--keepaspect"
assert_contains "$MPV_LOG" "--panscan=1.0"
assert_not_contains "$MPV_LOG" "--no-keepaspect"

: > "$MPV_LOG"
bash "$PIPELINE_SCRIPT" --playlist "$PLAYLIST" --scale-mode stretch --fullscreen no --loop-mode none --no-audio yes >/dev/null
assert_contains "$MPV_LOG" "--no-keepaspect"

# Slideshow parser order checks.
: > "$MPV_LOG"
bash "$SLIDESHOW_SCRIPT" "$MEDIA_DIR" >/dev/null
assert_contains "$MPV_LOG" "--image-display-duration=2.0"

: > "$MPV_LOG"
bash "$SLIDESHOW_SCRIPT" "$MEDIA_DIR" --scale-mode fill --duration 0.01 >/dev/null
assert_contains "$MPV_LOG" "--panscan=1.0"

: > "$MPV_LOG"
bash "$SLIDESHOW_SCRIPT" --scale-mode stretch "$MEDIA_DIR" --duration 0.01 >/dev/null
assert_contains "$MPV_LOG" "--no-keepaspect"

echo "PASS: slideshow scale mode semantics and parser order"
