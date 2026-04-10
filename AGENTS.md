# Agent notes — mpv-img-tricks

Concise orientation for coding assistants. End-user install and flags: [docs/setup.md](docs/setup.md). Deeper map: [docs/discovery.md](docs/discovery.md).

## What this repo is

- **Pre-alpha** utility: live image slideshows (**mpv**), optional **ffmpeg** flipbook render, **tile** mode via Bash.
- **Python** (`mpv_img_tricks/`): CLI, validation, **`plain_render`** (subprocess ffmpeg), routing to Bash for **basic** live and **tile**.
- **Bash** (`scripts/`): **`slideshow.sh`**, **`img-effects.sh`** (tile only), **`mpv-pipeline.sh`**, **`images-to-video.sh`** (legacy / optional direct use).

## Entrypoints

- Users run **`slideshow`** (e.g. `./slideshow` after `uv sync`, or `uv run slideshow`). Do not document **`scripts/*.sh`** as primary entrypoints.
- Routing summary:
  - **`live`** + **`basic`** → `scripts/slideshow.sh`
  - **`live`** + **`tile`** → `scripts/img-effects.sh`
  - **`--render`** (no **`--effect`**) → Python **`plain_render`** (not `images-to-video.sh` from the CLI)
  - **`--effect`** with **`--render`** is rejected

Defaults (e.g. duration **2.0**): `scripts/lib/constants.sh` and `mpv_img_tricks/cli.py`.

## Repo layout (high signal)

| Path | Role |
|------|------|
| `mpv_img_tricks/cli.py` | CLI, incompatible-arg checks |
| `mpv_img_tricks/pipelines/plain_render.py` | Plain flipbook render |
| `mpv_img_tricks/pipelines/live.py` | Live backend argv + subprocess |
| `mpv_img_tricks/paths.py` | Resolve repo root / `scripts/` (`MPV_IMG_TRICKS_ROOT`, `MPV_IMG_TRICKS_SCRIPTS_DIR`) |
| `scripts/mpv-pipeline.sh` | Shared mpv launch (scaling, instances, flags) |
| `scripts/lib/` | Shared Bash: `constants`, `path`, `pipeline`, `validate`, **`mpv_slideshow_bindings.sh`** |
| `mpv-scripts/slideshow-bindings.lua` | Live mpv key bindings; loaded via shared policy below |

## Slideshow mpv bindings (one policy)

- Script on disk: **`mpv-scripts/slideshow-bindings.lua`**.
- **`scripts/lib/mpv_slideshow_bindings.sh`** defines whether to add `--script=…`: CLI **`--use-slideshow-bindings`** (`mpv-pipeline.sh`) and **`MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS`** (non-empty disables everywhere, overrides CLI). **`img-effects.sh`** `run_mpv` uses the same helpers—keep them in sync if you change rules.

## Tests and CI

```bash
make test    # unit tests (bash + pytest)
make ci      # unit tests + scoped shellcheck (matches [.github/workflows/ci.yml](.github/workflows/ci.yml))
```

Harness: `tests/run-unit.sh` (needs **`uv`**, **`rg`**). Assertions: **`tests/unit/*.sh`** and **`tests/test_*.py`**. Optional ffmpeg smoke: [tests/manual/README.md](tests/manual/README.md).

## Conventions for changes

- Match existing naming, sourcing style, and error handling in touched files.
- Prefer small, behavior-focused diffs; avoid drive-by refactors unrelated to the task.
- After shell changes in CI scope, run **`make ci`** before commit when practical.
- Breaking CLI/env changes are acceptable for this project; update [docs/setup.md](docs/setup.md) and any tests that assert argv strings.
- **`--clear-cache`** (live): clears **`ffprobe-tile-v1`**, **`ffprobe-tile-v2`**, **`ffprobe-tile-v3`**, **`ffprobe-tile-v4`**, **`ffprobe-tile-v5`**, and **`tile-randomized`** under **`~/.cache/mpv-img-tricks/`** — from Python for basic live and plain **`--render`**, forwarded as **`--clear-cache`** to **`img-effects.sh`** for tile only.

## Docs you might edit

- **[docs/setup.md](docs/setup.md)** — prerequisites, env vars, mpv shortcuts, troubleshooting.
- **[docs/discovery.md](docs/discovery.md)** — architecture; update if control flow or major file roles change.
- **[README.md](README.md)** — user-facing overview; keep in sync for install and primary commands only.
