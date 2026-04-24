# Setup and environment

This page expands on [the main README](../README.md): prerequisites, how the CLI is wired, and environment variables.

## Prerequisites

| Need | Why |
|------|-----|
| **[uv](https://docs.astral.sh/uv/)** on your `PATH` | Required for `./slideshow` (it runs `uv run slideshow`) and for `./tests/run-unit.sh`. |
| **pytest** (via `uv sync`) | Unit tests are Python `pytest` under `tests/test_*.py` and are run by `./tests/run-unit.sh` / `make test`. |
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

**Default subcommand:** **`live`** — you may run **`slideshow ~/pics`** (or **`./slideshow ~/pics`**) instead of **`slideshow live ~/pics`** as long as the first argument is not a different subcommand name. Behavior is defined in **`mpv_img_tricks/cli.py`** (`DEFAULT_SUBCOMMAND`, `SUBCOMMAND_NAMES`).

**Sources:** Pass **one or more** positional **`SOURCE`** arguments (directories, image files, or glob patterns). Results are merged in order, deduplicated by real path, then ordered with **`--order`**: **`natural`** (version sort of paths, default), **`om`** (oldest modification time first), or **`nm`** (newest first). **`--shuffle`** overrides deterministic ordering (random playback). **`--watch`** requires **exactly one** directory source. Plain **`--render`** (flipbook) accepts the same multiple sources; **`scripts/images-to-video.sh`** also supports the legacy **`dir img_per_sec resolution output`** four-argument form when the second argument looks numeric and the third looks like **`1920x1080`**.

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
- `mpv-scripts/` — e.g. `slideshow-bindings.lua` for live controls.
- `pyproject.toml`, `uv.lock` — uv project and lockfile.

A published wheel contains only the Python package. **Running the full tool still expects this checkout** (or an equivalent tree with `scripts/` and `mpv-scripts/`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `MPV_IMG_TRICKS_ROOT` | Absolute path to the **repository root** (directory that contains `scripts/slideshow.sh`). Use if auto-discovery fails (unusual cwd, tooling that changes the working directory). |
| `MPV_IMG_TRICKS_SCRIPTS_DIR` | Absolute path to the legacy `scripts/` helper directory (for compatibility/tests that still touch shell helpers). |
| `MPV_IMG_TRICKS_DEFAULT_IMAGE_DIR` | When set, `scripts/slideshow.sh` uses this directory if no image path is passed on the command line (personal automation only). |
| `MPV_IMG_TRICKS_CONFIG` | Optional path to a **JSON** file with default CLI values (see below). If unset and `~/.config/mpv-img-tricks/config.json` exists, that file is loaded. |
| `MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS` | If non-empty, **all** slideshow mpv launches skip auto-loading **`mpv-scripts/slideshow-bindings.lua`** (overrides `--use-slideshow-bindings yes` on **`mpv-pipeline.sh`**). |
| `MPV_IMG_TRICKS_NO_FFPROBE_TILE_CACHE` | If non-empty, **`--effect tile`** validate-media does **not** read or write **`~/.cache/mpv-img-tricks/ffprobe-tile-v5`** (forces live **`ffprobe`** every run; use while debugging “everything skipped”). |
| `MPV_IMG_TRICKS_FFPROBE_VALIDATE_DEBUG` | If non-empty, **`--effect tile`** prints extra **stderr** lines: **`ffprobe`** path/version and step-by-step probe errors for up to **five** skipped files. When **all** files are skipped, **three** samples run automatically (still **stderr**) so a broken install (e.g. invalid **`ffprobe`** flags) is obvious without setting this first. |

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

## Slide duration

CLI flag **`--duration`** / **`-d`**: values are **seconds** (decimals allowed, e.g. `0.5`).

### Defaults

**`DEFAULT_SLIDESHOW_DURATION_SECONDS`** in [`scripts/lib/constants.sh`](../scripts/lib/constants.sh) (currently **2.0** s) mirrors the packaged CLI default (defined in `mpv_img_tricks/cli.py`). Override with **`--duration`** or JSON **`duration`** as usual.

### Live playback

| Mode | Meaning of `--duration` |
|------|-------------------------|
| **basic** | **Time each image stays on screen** in mpv (passed through the shared pipeline as image display duration). |
| **tile** | **Time each slide is shown**: mpv uses **`--image-display-duration`** for both the lavfi path and the playlist of pre-rendered composites. For **animated** tile segments (**`--animate-videos`**) or **temporal tile motion** (**`--tile-motion ken-burns`** or **`axis-alt`**), ffmpeg also uses **`--duration`** as **`-t`** (seconds) per short composite clip. |

### Plain render (`--render` without `--effect`)

Plain flipbook export runs in **Python** (`mpv_img_tricks.pipelines.plain_render`) and paces frames with **`--img-per-sec`**, not **`--duration`**. The **`--duration`** flag does not control per-image timing on that path. (The legacy script **`images-to-video.sh`** is still in the repo but is not invoked by the **`slideshow`** CLI.)

## mpv keyboard shortcuts

Live slideshows run **mpv** with the repo script **[`mpv-scripts/slideshow-bindings.lua`](../mpv-scripts/slideshow-bindings.lua)** (speed presets on **Alt+1**–**Alt+6**, **j**/**k** playlist, **m** keep, **Shift+Delete** trash, zoom/pan, **c** shuffle, **l** loop, etc.). That matches **README** → *Live Controls*.

| Code path | How bindings load |
|-----------|-------------------|
| **basic** | Via **`mpv-pipeline.sh`** (default **`--use-slideshow-bindings yes`**). |
| **tile** | Python tile pipeline (`mpv_img_tricks/pipelines/tile_live.py`) launches mpv directly with the same bindings policy. |
| **Disable bindings** | Set **`MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS=1`** (non-empty disables everywhere; overrides **`--use-slideshow-bindings yes`**). |

**Comparing machines:** bindings you like usually come from **this repo**, not from a global mpv profile—unless the other host also loads **`~/.config/mpv/input.conf`** or **`~/.config/mpv/scripts/*.lua`** and overrides the same keys.

Suggested diff checklist:

1. **Same checkout** — both machines need **`mpv-scripts/slideshow-bindings.lua`** at **`$REPO_ROOT/mpv-scripts/slideshow-bindings.lua`**. If the other machine only has an old clone or missing folder, you get stock mpv keys only.
2. **mpv user config** — on each machine:

   ```bash
   ls -la ~/.config/mpv/
   sed -n '1,200p' ~/.config/mpv/input.conf 2>/dev/null || true
   ls ~/.config/mpv/scripts/ 2>/dev/null || true
   ```

   Compare **`input.conf`** line by line: global binds can override or fight **`add_forced_key_binding`** in Lua depending on load order.
3. **What mpv actually got** — run a tiny session with debug (from repo root, example playlist):

   ```bash
   bash scripts/mpv-pipeline.sh --playlist /path/to/list.m3u --debug yes --instances 1
   ```

   Confirm the printed argv includes **`--script=.../mpv-scripts/slideshow-bindings.lua`**.

**Customizing shortcuts:** edit **`mpv-scripts/slideshow-bindings.lua`** in this repo (and commit if you want both machines aligned), or maintain a personal fork of that file and pass **`--extra-script`** / copy into **`~/.config/mpv/scripts/`**—avoid loading **two** copies of the same bindings twice (duplicate **`--script`** or autoload + CLI **`--script`**).

## Tiled slideshow: what runs before playback

For `--effect tile` (and similar compositing paths), work is not silent: phases are printed on stderr with the prefix `mpv-img-tricks:` when `--quiet` is not set. Rough order:

1. **validate-media** — Optional `ffprobe` pass over the playlist (progress lines every 25 files for large sets).
2. **probe-encoders** — With `--animate-videos`, lists ffmpeg encoders to pick VideoToolbox / fallback.
3. **prepare-audio** — Optional silence trim via ffmpeg when `--sound` is set.
4. **compositing-fixed** or **compositing-randomized** — Many short `ffmpeg` runs build slide composites (`-loglevel` rises with `--verbose-ffmpeg` or `--debug`). Concurrency is **bounded**: stderr includes a **`job_schedule`** line with `cpu_cap`, `tile_cap`, and RAM telemetry (`ram_cap_candidate` / `installed_ram_bytes`) plus whether `auto_ram_cap` is active. It also prints `limit_reason` so you can see which cap actually limited workers (`cpu`, `tile`, `ram`, or a tie like `tile+ram`). **`job_schedule`** includes **`temporal_composite`** and **`ram_bytes_per_worker`**: when **`true`** (Ken Burns, **`axis-alt`**, or **`--animate-videos`**), each concurrent encode is budgeted **more RAM headroom**, so **`ram_cap_candidate`** is usually **smaller** than for still-JPEG slides — fewer workers in flight to reduce swap / lockups on large libraries. With default settings, the RAM candidate participates in worker clamping; **`--no-auto-ram-cap`** removes that clamp (can increase pressure — only if you accept the risk). Slides are scheduled with at most that many workers in flight. Progress uses a carriage return on a TTY; when stderr is not a TTY (e.g. `2>&1 | tee log.txt`), newline status lines are emitted periodically.

   **Host memory snapshots:** right after **`job_schedule`**, **`mem_baseline`** logs approximate **`avail_mb`** (Linux **`MemAvailable`**; macOS **`vm_stat`** free+inactive pages — a rough hint) and **`rss_parent_mb`** for the **slideshow driver process** (from **`ps`**, not each `ffmpeg` child). During compositing, **`phase=compositing-mem`** repeats on a coarse schedule with the same fields so you can watch pressure while slides render. Use **`2>&1 | tee`** to capture both progress and memory lines.

If screen size detection fails (no usable `system_profiler` / `xrandr`), tile layout falls back to `--resolution`.

For large grids, tile safety defaults to `--tile-safe-mode auto`: if resolution is not explicit and the detected display is larger than 1280x720, very large grids are downscaled to a safer working resolution. Use `--tile-safe-mode warn` to keep current behavior with a recommendation log, or `--tile-safe-mode off` to disable it entirely.

Use `--tile-quality fast|balanced|high` to tune compositing quality/performance trade-offs:

- `fast` — lower-quality JPEG and faster scaler flags.
- `balanced` — default quality/perf compromise.
- `high` — higher-quality scaler flags and slower encode presets.

`--tile-hwaccel auto` enables an experimental hardware-acceleration path for animated tiles (`--animate-videos`) by requesting ffmpeg decode hwaccel and preferring VideoToolbox encoding on macOS when `--encoder auto` is used. In local A/B testing this mode was faster but had a slightly higher peak RSS; use `off` when minimizing memory is more important than speed. Keep `--tile-hwaccel off` (default) for the most predictable cross-platform behavior.

### Tile motion (Ken Burns and axis-alt)

- **`--tile-motion off|ken-burns|axis-alt`** (default **`off`**): slow pan/zoom **inside each tile cell** before stacking. **`ken-burns`** combines diagonal-style drift (with optional **`--tile-parallax auto`** variation). **`axis-alt`** alternates **pure axis** pan by column: even columns move **only on X**, odd columns **only on Y** (constant zoom so the path is a straight line). Still sources are looped for **`--duration`** seconds and encoded as short **MP4** slide files (not single-frame JPEG), so compositing costs more CPU/time than static tiles.
- **`--tile-parallax off|auto`** (default **`off`**): flip / vary pan direction in a deterministic way. **`--tile-parallax auto` requires `--tile-motion ken-burns` or `axis-alt`**.
- **`--tile-motion-strength`** (default **`1.0`**, must be **positive**): scales motion intensity; try **`0.5`**–**`2.0`** for tuning. Motion is rendered at **60 fps** inside each slide clip and the MP4 encoder uses the **same frame rate** so frames are not dropped to 30 fps (which looked choppy). Longer **`--duration`** (e.g. **4–8** seconds) makes pan/zoom easier to see on large grids.

Example:

```bash
uv run slideshow live ~/pics --effect tile --grid 2x2 --tile-motion ken-burns --tile-parallax auto --duration 3
```

Column-alternating drift:

```bash
uv run slideshow live ~/pics --effect tile --grid 3x3 --tile-motion axis-alt --tile-parallax auto --duration 4
```

## Routine checks

From the repository root (after `uv sync`):

| Command | What it runs |
|---------|----------------|
| `./tests/run-unit.sh` | Unit pytest suite (`uv sync` then `uv run pytest -q tests/`; same as CI **unit** job). Requires **`uv`**. |
| `make test` | Alias for `./tests/run-unit.sh`. |
| `make shellcheck` | Same **scoped** ShellCheck as CI (**shellcheck** on `PATH` required). |
| `make ci` | **`make test`** then **`make shellcheck`** — use this before a push to match CI. |
| `make manual-smoke` | **Not in CI.** Real **ffmpeg** encodes using `fixtures/images/`. See [tests/manual/README.md](../tests/manual/README.md). |

## CI and restricted environments

GitHub Actions and normal Linux/macOS runners are fine for `./tests/run-unit.sh`. For real compositing runs, heavily sandboxed environments can still restrict ffmpeg/mpv process behavior; if compositing tests fail with “Operation not permitted”, run the same command on a full VM or your laptop shell.

## Versioning

This project is **pre-alpha**. Breaking CLI or default-behavior changes are acceptable when they simplify the workflow; rely on git history and tags for snapshots if you need reproducibility.

## Troubleshooting

**`uv: command not found` when running `./slideshow`**

- Install uv, or run `.venv/bin/slideshow` after `uv sync`, or use `uv run slideshow` from the repo root.

**`Cannot find mpv-img-tricks repo root`**

- Run commands from inside the checkout, or set `MPV_IMG_TRICKS_ROOT` to that directory.

**Unit tests fail immediately**

- Ensure `uv` is on `PATH`. Tests run `uv sync` (preferring `--frozen` when `uv.lock` is present).

**Tile validate-media skipped every file (`kept=0`)**

- From the CLI: add **`--clear-cache`** on any **`live`** run (basic, tile, or plain **`--render`**) to remove **`ffprobe-tile-*`**, **`tile-randomized`**, and **`tile-fixed`** under **`~/.cache/mpv-img-tricks/`**, then continue the same run.
- Or delete manually:  
  `rm -rf ~/.cache/mpv-img-tricks/ffprobe-tile-v1 ~/.cache/mpv-img-tricks/ffprobe-tile-v2 ~/.cache/mpv-img-tricks/ffprobe-tile-v3 ~/.cache/mpv-img-tricks/ffprobe-tile-v4 ~/.cache/mpv-img-tricks/ffprobe-tile-v5`
- Or bypass the probe cache only (still uses composite cache):  
  `MPV_IMG_TRICKS_NO_FFPROBE_TILE_CACHE=1 slideshow … --effect tile …`
- If it still skips all paths, test one file:  
  `ffprobe -v error -i /path/to/one/image` — non-zero exit means **ffprobe/ffmpeg** cannot read that media (corrupt format, permissions, or missing codecs).
