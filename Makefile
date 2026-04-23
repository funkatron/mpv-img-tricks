# Local checks — mirrors .github/workflows/ci.yml jobs (unit + scoped shellcheck).
.PHONY: test pytest shellcheck ci manual-smoke

# Canonical suite: `tests/run-unit.sh` (uv sync + pytest)
test:
	./tests/run-unit.sh

# Pytest only (assumes venv/uv env already configured)
pytest:
	uv run pytest -q tests/

shellcheck:
	command -v shellcheck >/dev/null 2>&1 || { echo "Install shellcheck (e.g. brew install shellcheck)" >&2; exit 1; }
	shellcheck scripts/lib/*.sh
	shellcheck scripts/image-effects.sh
	shellcheck scripts/slideshow.sh
	shellcheck scripts/images-to-video.sh

ci: test shellcheck

# Real ffmpeg encodes (macOS-friendly); not run in CI.
manual-smoke:
	bash tests/manual/smoke-renders.sh
