#!/usr/bin/env bash
# Contract: tile validate-media must not pass -nostdin to ffprobe (broken on FFmpeg 8+).
set -euo pipefail

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "SKIP: ffprobe not on PATH"
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
touch "${WORK_DIR}/empty.jpg"

out_bad=$(ffprobe -nostdin -v error -threads 1 -i "${WORK_DIR}/empty.jpg" 2>&1 || true)
if [[ "$out_bad" != *"nostdin"* ]] && [[ "$out_bad" != *"Option not found"* ]]; then
  echo "expected -nostdin to be rejected by ffprobe; got: ${out_bad:0:500}"
  exit 1
fi

out_ok=$(ffprobe -v error -threads 1 -i "${WORK_DIR}/empty.jpg" 2>&1 || true)
if [[ "$out_ok" == *"Option not found"* ]] && [[ "$out_ok" == *"nostdin"* ]]; then
  echo "unexpected: plain ffprobe stderr looks like -nostdin parse error: ${out_ok:0:500}"
  exit 1
fi

echo "PASS: ffprobe rejects -nostdin; plain invocation does not report that option error"
