# Setup and environment

This page expands on [the main README](../README.md): prerequisites, how the CLI is wired, and environment variables.

## Prerequisites

| Need | Why |
|------|-----|
| **[uv](https://docs.astral.sh/uv/)** on your `PATH` | Required for `./slideshow` (it runs `uv run slideshow`) and for `./tests/run-unit.sh`. |
| **[ripgrep](https://github.com/BurntSushi/ripgrep)** (`rg`) | Unit tests under `tests/unit/*.sh` use `rg` for assertions. Install via your package manager (e.g. `brew install ripgrep`, `apt install ripgrep`). |
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
| `slideshow live …` (on `PATH`) | After you symlink or add `.venv/bin` to `PATH` — see below. |

**Package names:** PyPI-style name is `mpv-img-tricks`; Python import is `mpv_img_tricks`.

### Put `slideshow` on your `PATH`

After `uv sync`, the console script is **`.venv/bin/slideshow`**. Common options:

1. **Symlink** into a directory you already put on `PATH` (for example `~/bin`):

   ```bash
   mkdir -p ~/bin
   ln -sf /absolute/path/to/mpv-img-tricks/.venv/bin/slideshow ~/bin/slideshow
   ```

   Use the **real absolute path** to your clone. In `~/.zshrc` (or your shell config), ensure `~/bin` is on `PATH`, e.g. `export PATH="$HOME/bin:$PATH"`.

   If you remove the venv (`rm -rf .venv`) or move the repo, recreate the symlink or point it at the new `.venv/bin/slideshow`.

2. **Prefix `PATH`** with `.venv/bin` for this project only, e.g. in `~/.zshrc`:

   ```bash
   export PATH="/absolute/path/to/mpv-img-tricks/.venv/bin:$PATH"
   ```

3. **direnv** in the repo: `export PATH="$PWD/.venv/bin:$PATH"` in `.envrc` so `slideshow` is available whenever you `cd` into the checkout.

Prefer **`.venv/bin/slideshow`** over adding the repo-root `./slideshow` script to `PATH`: the repo helper shells out to `uv run` and still needs `uv` on `PATH`; the venv binary does not.

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
| `MPV_IMG_TRICKS_DEFAULT_IMAGE_DIR` | When set, `scripts/slideshow.sh` uses this directory if no image path is passed on the command line (personal automation only). |
| `MPV_IMG_TRICKS_CONFIG` | Optional path to a **JSON** file with default CLI values (see below). If unset and `~/.config/mpv-img-tricks/config.json` exists, that file is loaded. |

## Optional JSON defaults

Merge order: built-in argparse defaults, then keys from the config file, then explicit CLI flags (CLI always wins). Supported keys (omit any you do not need):

- `duration`, `scale_mode`, `resolution`, `fps`, `img_per_sec`, `limit` (strings or numbers coerced as for CLI)
- `quiet`, `debug`, `verbose_ffmpeg` (booleans)

Example `~/.config/mpv-img-tricks/config.json`:

```json
{
  "duration": "3.0",
  "scale_mode": "fit",
  "quiet": false,
  "debug": false
}
```

## Tiled slideshow: what runs before playback

For `--effect tile` (and similar compositing paths), work is not silent: phases are printed on stderr with the prefix `mpv-img-tricks:` when `--quiet` is not set. Rough order:

1. **validate-media** — Optional `ffprobe` pass over the playlist (progress lines every 25 files for large sets).
2. **probe-encoders** — With `--animate-videos`, lists ffmpeg encoders to pick VideoToolbox / fallback.
3. **prepare-audio** — Optional silence trim via ffmpeg when `--sound` is set.
4. **compositing-fixed** or **compositing-randomized** — Many short `ffmpeg` runs build slide composites (`-loglevel` rises with `--verbose-ffmpeg` or `--debug`). Progress uses a carriage return on a TTY; when stderr is not a TTY (e.g. `2>&1 | tee log.txt`), newline status lines are emitted every few slides.

If screen size detection fails (no usable `system_profiler` / `xrandr`), tile layout falls back to `--resolution`.

## CI and restricted environments

GitHub Actions and normal Linux/macOS runners are fine for `./tests/run-unit.sh`. Some **sandboxed** or highly locked-down environments block `nice(2)` or bash process substitution used inside `img-effects.sh`; if compositing tests fail with “Operation not permitted”, run the same command on a full VM or your laptop shell.

## Versioning

This project is **pre-alpha**. Breaking CLI or default-behavior changes are acceptable when they simplify the workflow; rely on git history and tags for snapshots if you need reproducibility.

## Troubleshooting

**`uv: command not found` when running `./slideshow`**

- Install uv, or run `.venv/bin/slideshow` after `uv sync`, or use `uv run slideshow` from the repo root.

**`Cannot find mpv-img-tricks repo root`**

- Run commands from inside the checkout, or set `MPV_IMG_TRICKS_ROOT` to that directory.

**Unit tests fail immediately**

- Ensure `uv` is on `PATH`. Tests run `uv sync` (preferring `--frozen` when `uv.lock` is present).
