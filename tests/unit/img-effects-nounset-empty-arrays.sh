#!/usr/bin/env bash
# Regression: bash 3.2 (macOS default) + set -u errors on "${arr[@]}" when arr is
# declared but empty. img-effects.sh uses "${arr[@]+"${arr[@]}"}" for optional
# ffmpeg args (stats, VIDEO_A_EXTRA). See run_composite_ffmpeg, run_ffmpeg_effect_hevc.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG_EFFECTS="${ROOT_DIR}/scripts/img-effects.sh"

fail() {
  echo "TEST FAILED: $1"
  exit 1
}

if ! command -v ffmpeg >/dev/null 2>&1; then
  fail "ffmpeg required on PATH for nounset expansion smoke test"
fi

# 1) Behavior: same expansions as img-effects.sh must not trip nounset.
mirror_run_composite_ffmpeg_stats() {
  local logl=error
  local stats=()
  # Verbose off: stats stays empty (matches production default).
  run_under_nice() { "$@"; }
  run_under_nice ffmpeg -nostdin -loglevel "$logl" "${stats[@]+"${stats[@]}"}" -threads 1 -version >/dev/null
}

mirror_run_ffmpeg_effect_hevc_extras() {
  local logl=error
  local stats=()
  local VIDEO_A_EXTRA=()
  ffmpeg -nostdin -loglevel "$logl" "${stats[@]+"${stats[@]}"}" -version >/dev/null
  ffmpeg -nostdin -loglevel "$logl" "${VIDEO_A_EXTRA[@]+"${VIDEO_A_EXTRA[@]}"}" -version >/dev/null
}

mirror_run_composite_ffmpeg_stats
mirror_run_ffmpeg_effect_hevc_extras

# 2) Guard: source file must keep nounset-safe patterns (catch accidental revert).
if ! command -v rg >/dev/null 2>&1; then
  fail "rg required (same as other unit tests)"
fi
if ! rg -F --quiet '${stats[@]+"${stats[@]}"}' "$IMG_EFFECTS"; then
  fail "expected nounset-safe stats expansion in img-effects.sh"
fi
if ! rg -F --quiet '${VIDEO_A_EXTRA[@]+"${VIDEO_A_EXTRA[@]}"}' "$IMG_EFFECTS"; then
  fail "expected nounset-safe VIDEO_A_EXTRA expansion in img-effects.sh"
fi

echo "PASS: img-effects nounset empty-array ffmpeg expansions"
