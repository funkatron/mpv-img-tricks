#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

slideshow() {
  (cd "$ROOT_DIR" && uv run slideshow "$@")
}

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

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
MEDIA_DIR="${WORK_DIR}/media"
BACKEND_DIR="${WORK_DIR}/backends"
LOG_FILE="${WORK_DIR}/backend.log"
mkdir -p "$MEDIA_DIR" "$BACKEND_DIR" "${WORK_DIR}/bin"
# Minimal valid 1x1 PNGs so plain --render (real ffmpeg) succeeds when exercised.
python3 - <<PY
import base64
from pathlib import Path
png = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)
d = Path("${MEDIA_DIR}")
(d / "a.png").write_bytes(png)
(d / "b.png").write_bytes(png)
PY

cat > "${BACKEND_DIR}/slideshow.sh" <<'EOF'
#!/usr/bin/env bash
printf 'slideshow.sh %s\n' "$*" >> "$BACKEND_LOG"
exit 0
EOF

cat > "${BACKEND_DIR}/images-to-video.sh" <<'EOF'
#!/usr/bin/env bash
printf 'images-to-video.sh %s\n' "$*" >> "$BACKEND_LOG"
exit 0
EOF

chmod +x "${BACKEND_DIR}/slideshow.sh" "${BACKEND_DIR}/images-to-video.sh"

cat > "${WORK_DIR}/bin/mpv" <<'EOF'
#!/usr/bin/env bash
printf 'mpv %s\n' "$*" >> "$BACKEND_LOG"
exit 0
EOF
chmod +x "${WORK_DIR}/bin/mpv"

export BACKEND_LOG="${LOG_FILE}"
export MPV_IMG_TRICKS_SCRIPTS_DIR="${BACKEND_DIR}"
export PATH="${WORK_DIR}/bin:${PATH}"

slideshow --help >/dev/null
slideshow live --help >"${WORK_DIR}/help.txt"
assert_contains "${WORK_DIR}/help.txt" "playback/display"
assert_contains "${WORK_DIR}/help.txt" "render/video"
assert_contains "${WORK_DIR}/help.txt" "effect-specific"
assert_contains "${WORK_DIR}/help.txt" "dry-run"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --dry-run --duration 0.01 --scale-mode fill >"${WORK_DIR}/dry.txt"
assert_contains "${WORK_DIR}/dry.txt" "mpv"
assert_contains "${WORK_DIR}/dry.txt" "--playlist="
assert_contains "${WORK_DIR}/dry.txt" "--image-display-duration=0.01"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --duration 0.01 --scale-mode fill >/dev/null
assert_contains "$LOG_FILE" "mpv "
assert_contains "$LOG_FILE" "--image-display-duration=0.01"
assert_contains "$LOG_FILE" "--playlist="

: > "$LOG_FILE"
slideshow "$MEDIA_DIR" --duration 0.01 --scale-mode fill >/dev/null
assert_contains "$LOG_FILE" "mpv "
assert_contains "$LOG_FILE" "--playlist="

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --duration 0.01 --fill >/dev/null
assert_contains "$LOG_FILE" "mpv "
assert_contains "$LOG_FILE" "--panscan=1.0"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --duration 0.01 --fit >/dev/null
assert_contains "$LOG_FILE" "mpv "
assert_contains "$LOG_FILE" "--panscan=0.0"

if slideshow live "$MEDIA_DIR" --fit --fill >/dev/null 2>"${WORK_DIR}/mx.err"; then
  fail "expected --fit and --fill together to fail"
fi
rg -q "mutually exclusive|not allowed" "${WORK_DIR}/mx.err" || rg -q "argument" "${WORK_DIR}/mx.err" || fail "expected argparse error for --fit --fill"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --effect tile --grid 2x2 --randomize --duration 0.01 >/dev/null
assert_contains "$LOG_FILE" "mpv "

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --effect tile --grid 1x1 --instances 2 --display-map 0,1 --master-control --duration 0.01 >/dev/null
assert_contains "$LOG_FILE" "mpv "
assert_contains "$LOG_FILE" "--input-ipc-server="
assert_contains "$LOG_FILE" "--fs-screen=0"
assert_contains "$LOG_FILE" "--fs-screen=1"

: > "${WORK_DIR}/dry-clear.txt"
slideshow live "$MEDIA_DIR" --effect tile --grid 1x1 --clear-cache --dry-run >"${WORK_DIR}/dry-clear.txt"
assert_contains "${WORK_DIR}/dry-clear.txt" "--clear-cache"
assert_contains "${WORK_DIR}/dry-clear.txt" "python-tile-live"

: > "$LOG_FILE"
if ! slideshow live "$MEDIA_DIR" --clear-cache --duration 0.01 >/dev/null 2>"${WORK_DIR}/clear-basic.err"; then
  fail "expected --clear-cache with basic live to succeed"
fi
assert_contains "${WORK_DIR}/clear-basic.err" "phase=cache"
assert_contains "$LOG_FILE" "mpv "
assert_contains "$LOG_FILE" "--playlist="

: > "$LOG_FILE"
if ! slideshow live "$MEDIA_DIR" --render --output out.mp4 --clear-cache >/dev/null 2>"${WORK_DIR}/clear-render.err"; then
  fail "expected --clear-cache with plain --render to succeed"
fi
assert_contains "${WORK_DIR}/clear-render.err" "phase=cache"

slideshow live "$MEDIA_DIR" --render --output out.mp4 --dry-run >"${WORK_DIR}/dry-render.txt"
assert_contains "${WORK_DIR}/dry-render.txt" "ffmpeg"
assert_contains "${WORK_DIR}/dry-render.txt" "plain-render"

if slideshow live "$MEDIA_DIR" --render --effect tile >/dev/null 2>"${WORK_DIR}/er1.log"; then
  fail "expected --effect with --render to fail"
fi
assert_contains "${WORK_DIR}/er1.log" "cannot be combined with --render"

if slideshow live "$MEDIA_DIR" --effect chaos >/dev/null 2>"${WORK_DIR}/er2.log"; then
  fail "expected chaos effect to be invalid"
fi
assert_contains "${WORK_DIR}/er2.log" "invalid choice"

mkdir -p "${MEDIA_DIR}/sub"
slideshow live "$MEDIA_DIR" "${MEDIA_DIR}/sub" --dry-run --duration 0.01 >"${WORK_DIR}/dry-multi.txt"
assert_contains "${WORK_DIR}/dry-multi.txt" "mpv"
assert_contains "${WORK_DIR}/dry-multi.txt" "--playlist="

if slideshow live "$MEDIA_DIR" "${MEDIA_DIR}/sub" --watch >/dev/null 2>"${WORK_DIR}/watch.err"; then
  fail "expected --watch with multiple sources to fail"
fi
assert_contains "${WORK_DIR}/watch.err" "requires exactly one source path"

echo "PASS: unified slideshow CLI routes live/tile/plain-render modes"
