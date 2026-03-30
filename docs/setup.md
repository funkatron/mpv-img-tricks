# Setup and environment

This page expands on [the main README](../README.md): prerequisites, how the CLI is wired, and environment variables.

## Prerequisites

| Need | Why |
|------|-----|
| **[uv](https://docs.astral.sh/uv/)** on your `PATH` | Required for `./slideshow` (it runs `uv run slideshow`) and for `./tests/run-unit.sh`. |
| **Python 3.11+** | Declared in `pyproject.toml`; uv installs/selects a compatible interpreter. |
| **Bash** | Backend scripts under `scripts/` are Bash. |
| **mpv** | Live slideshow playback. |
| **ffmpeg** | Video rendering and effects. |
| **fswatch** (optional) | `--watch` mode; e.g. `brew install fswatch` on macOS. |

Install uv using the official installer from the Astral docs if you do not have it yet.

## Install from a clone

```bash
git clone <your-fork-or-upstream-url> mpv-img-tricks
cd mpv-img-tricks
uv sync
```

That creates `.venv/` and installs this project in **editable** mode (see `uv.lock` for the resolved environment).

## Ways to run the CLI

| Command | Notes |
|---------|--------|
| `./slideshow live …` | Repo-root helper; **requires `uv` on `PATH`**. |
| `uv run slideshow live …` | Same entrypoint; uses the project environment. |
| `uv run python -m mpv_img_tricks live …` | Module invocation; same behavior. |
| `.venv/bin/slideshow live …` | Works after `uv sync` **without** typing `uv` each time (still need the venv). |

**Package names:** PyPI-style name is `mpv-img-tricks`; Python import is `mpv_img_tricks`.

## Repository layout (high level)

- `mpv_img_tricks/` — Python package (CLI + `get_repo_root` / `get_scripts_dir`).
- `scripts/` — Bash backends (not intended as direct user entrypoints).
- `mpv-scripts/` — e.g. `blast.lua` for live controls.
- `pyproject.toml`, `uv.lock` — uv project and lockfile.

A published wheel contains only the Python package. **Running the full tool still expects this checkout** (or an equivalent tree with `scripts/` and `mpv-scripts/`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `MPV_IMG_TRICKS_ROOT` | Absolute path to the **repository root** (directory that contains `scripts/slideshow.sh`). Use if auto-discovery fails (unusual cwd, tooling that changes the working directory). |
| `MPV_IMG_TRICKS_SCRIPTS_DIR` | Absolute path to the directory that contains `slideshow.sh`, `img-effects.sh`, and `images-to-video.sh`. Overrides normal `scripts/` resolution (used by unit tests with mock backends). |

## Troubleshooting

**`uv: command not found` when running `./slideshow`**

- Install uv, or run `.venv/bin/slideshow` after `uv sync`, or use `uv run slideshow` from the repo root.

**`Cannot find mpv-img-tricks repo root`**

- Run commands from inside the checkout, or set `MPV_IMG_TRICKS_ROOT` to that directory.

**Unit tests fail immediately**

- Ensure `uv` is on `PATH`. Tests run `uv sync` (preferring `--frozen` when `uv.lock` is present).
