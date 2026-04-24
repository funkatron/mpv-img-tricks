# Manual effect checks (real ffmpeg)

Automated coverage lives in `tests/test_*.py` (pytest, with stubs where needed). Use this folder when you want **real encodes** and **quick eyeballing** on your Mac.

## One-time: tiny fixtures

From repo root (needs **ffmpeg** on `PATH`):

```bash
./tests/manual/generate-fixtures.sh
```

Creates `fixtures/images/*.png` (solid colors). These paths are under `fixtures/` so they can be tracked or regenerated; ignore rules allow `fixtures/**/*`.

## Render smokes (no mpv window)

```bash
./tests/manual/smoke-renders.sh
```

Writes videos under `tmp/effect-smoke/` (gitignored) and prints `ffprobe` duration/size. Fails if any encode exits non-zero.

**Tile live** is interactive (fullscreen mpv); exercise it yourself, for example:

```bash
./slideshow live fixtures/images --effect tile --grid 2x2 --duration 2 --no-cache
```

Use your own image directory for serious checks.

## Routine

- Daily: `make test` (or `make ci` with shellcheck installed).
- After changing **tile** or **plain render**: `make test` plus `./tests/manual/smoke-renders.sh`.
