#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v uv >/dev/null 2>&1; then
  echo "Unit tests require uv: https://docs.astral.sh/uv/" >&2
  exit 1
fi

(cd "$ROOT_DIR" && uv sync --frozen) || (cd "$ROOT_DIR" && uv sync)
(cd "$ROOT_DIR" && uv run pytest -q tests/)

echo "OK: pytest (tests/)" >&2
