#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/tests/unit"

if [ ! -d "$TEST_DIR" ]; then
  echo "No unit tests found: $TEST_DIR"
  exit 1
fi

total=0
passed=0

while IFS= read -r test_file; do
  [ -n "$test_file" ] || continue
  total=$((total + 1))
  echo "Running $(basename "$test_file")"
  if bash "$test_file"; then
    passed=$((passed + 1))
  else
    echo "FAILED: $test_file"
    exit 1
  fi
done < <(find "$TEST_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

echo "Unit tests passed: ${passed}/${total}"
