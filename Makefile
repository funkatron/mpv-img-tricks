# Local checks — mirrors .github/workflows/ci.yml jobs (unit + scoped shellcheck).
.PHONY: test shellcheck ci

test:
	./tests/run-unit.sh

shellcheck:
	command -v shellcheck >/dev/null 2>&1 || { echo "Install shellcheck (e.g. brew install shellcheck)" >&2; exit 1; }
	shellcheck scripts/lib/*.sh
	shellcheck scripts/image-effects.sh
	shellcheck scripts/slideshow.sh
	shellcheck scripts/images-to-video.sh

ci: test shellcheck
