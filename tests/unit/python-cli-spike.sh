#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_PATH="${ROOT_DIR}/python/slideshow_cli.py"

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
touch "${MEDIA_DIR}/a.jpg"

MPV_LOG="${WORK_DIR}/mpv.log"
export MPV_LOG

cat > "${BIN_DIR}/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MPV_LOG"
exit 0
EOF
chmod +x "${BIN_DIR}/mpv"
export PATH="${BIN_DIR}:$PATH"

python3 "$CLI_PATH" --help >/dev/null
python3 "$CLI_PATH" live --help >/dev/null
python3 "$CLI_PATH" tile --help >/dev/null
python3 "$CLI_PATH" render --help >/dev/null

python3 "$CLI_PATH" live "$MEDIA_DIR" --duration 0.01 --scale-mode fill >/dev/null
assert_contains "$MPV_LOG" "--panscan=1.0"

echo "PASS: python CLI spike parse and live bridge"
