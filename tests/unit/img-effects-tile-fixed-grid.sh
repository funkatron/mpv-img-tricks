#!/usr/bin/env bash
# Fixed grid tile path (no --randomize): lavfi-complex + mpv when inputs == tile count and spacing == 0.
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

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BIN_DIR="${WORK_DIR}/bin"
MEDIA_DIR="${WORK_DIR}/media"
mkdir -p "$BIN_DIR" "$MEDIA_DIR"

touch "${MEDIA_DIR}/a.jpg" "${MEDIA_DIR}/b.jpg"

MPV_LOG="${WORK_DIR}/mpv.log"
export MPV_LOG

cat > "${BIN_DIR}/ffprobe" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${BIN_DIR}/system_profiler" <<'EOF'
#!/usr/bin/env bash
echo "Resolution: 1920 x 1080"
EOF

cat > "${BIN_DIR}/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MPV_LOG"
exit 0
EOF

chmod +x "${BIN_DIR}/ffprobe" "${BIN_DIR}/system_profiler" "${BIN_DIR}/mpv"

export PATH="${BIN_DIR}:$PATH"

bash "$SCRIPT_PATH" tile "$MEDIA_DIR" \
  --grid 2x1 --duration 0.2 --no-cache >/dev/null

assert_contains "$MPV_LOG" "--lavfi-complex="
assert_contains "$MPV_LOG" "xstack=inputs=2"

echo "PASS: img-effects tile fixed grid lavfi path"
