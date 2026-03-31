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
mkdir -p "$MEDIA_DIR" "$BACKEND_DIR"
touch "${MEDIA_DIR}/a.jpg" "${MEDIA_DIR}/b.jpg"

cat > "${BACKEND_DIR}/slideshow.sh" <<'EOF'
#!/usr/bin/env bash
printf 'slideshow.sh %s\n' "$*" >> "$BACKEND_LOG"
exit 0
EOF

cat > "${BACKEND_DIR}/img-effects.sh" <<'EOF'
#!/usr/bin/env bash
printf 'img-effects.sh %s\n' "$*" >> "$BACKEND_LOG"
exit 0
EOF

cat > "${BACKEND_DIR}/images-to-video.sh" <<'EOF'
#!/usr/bin/env bash
printf 'images-to-video.sh %s\n' "$*" >> "$BACKEND_LOG"
exit 0
EOF

chmod +x "${BACKEND_DIR}/slideshow.sh" "${BACKEND_DIR}/img-effects.sh" "${BACKEND_DIR}/images-to-video.sh"

export BACKEND_LOG="${LOG_FILE}"
export MPV_IMG_TRICKS_SCRIPTS_DIR="${BACKEND_DIR}"

slideshow --help >/dev/null
slideshow live --help >"${WORK_DIR}/help.txt"
assert_contains "${WORK_DIR}/help.txt" "playback/display"
assert_contains "${WORK_DIR}/help.txt" "render/video"
assert_contains "${WORK_DIR}/help.txt" "effect-specific"
assert_contains "${WORK_DIR}/help.txt" "dry-run"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --dry-run --duration 0.01 --scale-mode fill >"${WORK_DIR}/dry.txt"
assert_contains "${WORK_DIR}/dry.txt" "slideshow.sh"
assert_contains "${WORK_DIR}/dry.txt" "${MEDIA_DIR}"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --duration 0.01 --scale-mode fill >/dev/null
assert_contains "$LOG_FILE" "slideshow.sh ${MEDIA_DIR} --duration 0.01 --scale-mode fill --instances 1"

: > "$LOG_FILE"
slideshow "$MEDIA_DIR" --duration 0.01 --scale-mode fill >/dev/null
assert_contains "$LOG_FILE" "slideshow.sh ${MEDIA_DIR} --duration 0.01 --scale-mode fill --instances 1"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --duration 0.01 --fill >/dev/null
assert_contains "$LOG_FILE" "slideshow.sh ${MEDIA_DIR} --duration 0.01 --scale-mode fill --instances 1"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --duration 0.01 --fit >/dev/null
assert_contains "$LOG_FILE" "slideshow.sh ${MEDIA_DIR} --duration 0.01 --scale-mode fit --instances 1"

if slideshow live "$MEDIA_DIR" --fit --fill >/dev/null 2>"${WORK_DIR}/mx.err"; then
  fail "expected --fit and --fill together to fail"
fi
rg -q "mutually exclusive|not allowed" "${WORK_DIR}/mx.err" || rg -q "argument" "${WORK_DIR}/mx.err" || fail "expected argparse error for --fit --fill"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --effect chaos --duration 0.01 >/dev/null
assert_contains "$LOG_FILE" "img-effects.sh chaos ${MEDIA_DIR} --duration 0.01 --scale-mode fit --instances 1"

: > "$LOG_FILE"
slideshow live "${MEDIA_DIR}/*.mov" --effect tile --grid 2x2 --randomize --duration 0.01 >/dev/null
assert_contains "$LOG_FILE" "img-effects.sh tile ${MEDIA_DIR}/*.mov --duration 0.01 --scale-mode fit --instances 1 --grid 2x2 --randomize"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --render --output out.mp4 >/dev/null
assert_contains "$LOG_FILE" "images-to-video.sh ${MEDIA_DIR} 60 1920x1080 out.mp4"

: > "$LOG_FILE"
slideshow live "$MEDIA_DIR" --render --effect glitch --output glitch.mp4 --duration 0.3 >/dev/null
assert_contains "$LOG_FILE" "img-effects.sh glitch ${MEDIA_DIR} --duration 0.3 --resolution 1920x1080 --fps 30 --output glitch.mp4 --scale-mode fit --limit 5"

if slideshow live "$MEDIA_DIR" --effect glitch >/dev/null 2>"${WORK_DIR}/err.log"; then
  fail "expected glitch without --render to fail"
fi
assert_contains "${WORK_DIR}/err.log" "requires --render"

echo "PASS: unified slideshow CLI routes live/effect/render modes"
