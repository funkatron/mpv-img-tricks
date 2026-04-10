#!/usr/bin/env bash
# shellcheck disable=SC1091
# Thin shim: live basic slideshow runs in Python (``slideshow live``). This keeps
# ``scripts/slideshow.sh`` discoverable for repo-root detection and legacy callers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

exec uv run slideshow live "$@"
