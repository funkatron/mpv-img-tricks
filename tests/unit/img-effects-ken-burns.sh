#!/usr/bin/env bash
# Ken-burns render: assert ffmpeg argv contains zoompan graph and integer zoompan d= (not duration*fps text).
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
    sed -n '1,200p' "$file" || true
    fail "missing expected pattern"
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if rg -F --quiet -- "$pattern" "$file"; then
    echo "Unexpected pattern found: $pattern"
    fail "unexpected pattern"
  fi
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BIN_DIR="${WORK_DIR}/bin"
MEDIA_DIR="${WORK_DIR}/media"
mkdir -p "$BIN_DIR" "$MEDIA_DIR"

touch "${MEDIA_DIR}/a.jpg" "${MEDIA_DIR}/b.jpg"

FFMPEG_LOG="${WORK_DIR}/ffmpeg.log"
export FFMPEG_LOG

cat > "${BIN_DIR}/ffmpeg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FFMPEG_LOG"
out_file="${!#}"
mkdir -p "$(dirname "$out_file")"
touch "$out_file"
exit 0
EOF

chmod +x "${BIN_DIR}/ffmpeg"

export PATH="${BIN_DIR}:$PATH"

OUT_MP4="${WORK_DIR}/out.mp4"
bash "$SCRIPT_PATH" ken-burns "$MEDIA_DIR" \
  --limit 2 --duration 1 --fps 30 --resolution 640x480 --output "$OUT_MP4" >/dev/null

assert_contains "$FFMPEG_LOG" "zoompan="
assert_contains "$FFMPEG_LOG" "concat=n=2"
assert_contains "$FFMPEG_LOG" "-c:v hevc_videotoolbox"
assert_contains "$FFMPEG_LOG" ":d=30:"
assert_not_contains "$FFMPEG_LOG" "d=1*30"
assert_not_contains "$FFMPEG_LOG" "d=0.05*30"

echo "PASS: img-effects ken-burns ffmpeg graph"
