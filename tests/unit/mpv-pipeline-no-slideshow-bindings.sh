#!/usr/bin/env bash
# MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS skips --script for slideshow-bindings.lua on mpv-pipeline.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPELINE_SCRIPT="${ROOT_DIR}/scripts/mpv-pipeline.sh"

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

touch "${MEDIA_DIR}/a.jpg"
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

# Default: bindings script is passed when file exists.
bash "$PIPELINE_SCRIPT" --playlist "$PLAYLIST" --fullscreen no --loop-mode none --no-audio yes >/dev/null
assert_contains "$MPV_LOG" "mpv-scripts/slideshow-bindings.lua"

: > "$MPV_LOG"
export MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS=1
bash "$PIPELINE_SCRIPT" --playlist "$PLAYLIST" --fullscreen no --loop-mode none --no-audio yes >/dev/null
assert_not_contains "$MPV_LOG" "slideshow-bindings.lua"

unset MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS

echo "PASS: mpv-pipeline respects MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS"
