# mpv-img-tricks

**⚠️ PRE-ALPHA SOFTWARE** - Experimental software in early development. Use at your own risk!

Image slideshow and effects system for building live slideshows and rendered videos from image collections.

**Primary command:** `./slideshow live` from the repository root (after setup below). You can usually omit **`live`**: if the first argument is not another subcommand name, it defaults to **`live`**. For example, `./slideshow ~/pics` matches `./slideshow live ~/pics`. (Constants: **`DEFAULT_SUBCOMMAND`** / **`SUBCOMMAND_NAMES`** in `mpv_img_tricks/cli.py`.)

This is a personal utility project. Breaking CLI changes are acceptable when they simplify the workflow.

**More detail:** [docs/setup.md](docs/setup.md) — prerequisites (`uv`, Python 3.11+, mpv, ffmpeg), all ways to invoke the CLI, environment variables, and troubleshooting.

**Architecture and maintenance:** [docs/discovery.md](docs/discovery.md) — how the Python CLI maps to Bash backends, test coverage, and where to change behavior.

**Improvement ideas (prioritized):** [docs/recommendations.md](docs/recommendations.md) — UX, testing/CI, portability, Python vs Bash boundary, security, repo hygiene.

## Development (tests before push)

After **`uv sync`**, run the same checks CI uses:

```bash
make ci
```

That runs **`./tests/run-unit.sh`** (needs **`uv`** and **`rg`**) plus **shellcheck** on the scoped Bash scripts. Use **`make test`** for unit tests only. Details: [.github/workflows/ci.yml](.github/workflows/ci.yml), [docs/setup.md](docs/setup.md#routine-checks).

**Real ffmpeg checks** (optional, after changing tile/ken-burns or effects): [tests/manual/README.md](tests/manual/README.md) — run **`./tests/manual/generate-fixtures.sh`** once, then **`make manual-smoke`** (needs **ffmpeg** / **ffprobe** on `PATH`; writes under **`tmp/effect-smoke/`**).

## Requirements (summary)

- **[uv](https://docs.astral.sh/uv/)** on your `PATH` for `./slideshow` and for `./tests/run-unit.sh`.
- **[ripgrep](https://github.com/BurntSushi/ripgrep)** (`rg`) for `./tests/run-unit.sh` (assertions in `tests/unit/*.sh`).
- **Python 3.11+**, **Bash**, **mpv**, and **ffmpeg** for real runs (versions are up to you; the CLI shells out to the Bash backends).
- **fswatch** only if you use `--watch` (see [docs/setup.md](docs/setup.md)).

**Defaults:** Omitted `--duration` uses **2.0** seconds per image (packaged CLI). The shared value lives in [`scripts/lib/constants.sh`](scripts/lib/constants.sh). Use `--duration 0.02` (or lower) for rapid cycling. **How duration applies** (live vs tile vs ffmpeg effects vs plain `--render`): [docs/setup.md](docs/setup.md#slide-duration).

## Installation

This repository is a **[uv](https://docs.astral.sh/uv/)** project (`pyproject.toml`, `uv.lock`). From the checkout:

```bash
uv sync
```

That creates `.venv/` and installs the **`mpv-img-tricks`** package in editable mode (import name **`mpv_img_tricks`**).

**Run the CLI** (equivalent behavior):

| Invocation | When to use |
|------------|-------------|
| `./slideshow live …` | Default subcommand; same as `uv run slideshow` from repo root. |
| `./slideshow …` (no subcommand) | Same as **`live`** when the first token is a path, glob, or option (not a reserved subcommand name). |
| `uv run slideshow live …` | Explicit project environment. |
| `uv run python -m mpv_img_tricks live …` | Module entry (`python -m mpv_img_tricks`). |
| `.venv/bin/slideshow live …` | After `uv sync`, without needing `uv` on the shell line. |

To use the bare command `slideshow` from anywhere, put `.venv/bin` on your `PATH` or symlink `.venv/bin/slideshow` into e.g. `~/bin` — see [docs/setup.md](docs/setup.md#put-slideshow-on-your-path).

**Library use:** `from mpv_img_tricks import get_scripts_dir, get_repo_root, main` or `from mpv_img_tricks.cli import main` for the same entrypoint the `slideshow` console script calls.

**Environment variables** (full table in [docs/setup.md](docs/setup.md)):

- **`MPV_IMG_TRICKS_ROOT`** — Force repository root when auto-discovery fails.
- **`MPV_IMG_TRICKS_SCRIPTS_DIR`** — Force the `scripts/` directory (tests and custom layouts).

Examples:
```bash
./slideshow ~/pics                      # same as: ./slideshow live ~/pics
./slideshow live ~/pics
./slideshow live ~/pics --effect chaos --duration 0.02
./slideshow live ~/pics --render --output out.mp4
```

## Quick Start

### Simple Slideshows

```bash
# Basic slideshow
./slideshow live ~/pics

# Chaos mode (shuffled, infinite loop)
./slideshow live ~/pics --effect chaos --duration 0.02

# Slideshow with scaling options
./slideshow live ~/pics --scale-mode fill
```

### Video Effects

```bash
# Ken Burns effect
./slideshow live ~/pics --render --effect ken-burns --duration 3 --output slideshow.mp4

# Visual effects (glitch, acid, reality, etc.)
./slideshow live ~/pics --render --effect glitch --output glitch.mp4
./slideshow live ~/pics --render --effect acid --output acid-trip.mp4
./slideshow live ~/pics --render --effect reality --output reality-break.mp4

# Simple video from images
./slideshow live ~/pics --render --img-per-sec 60 --resolution 1920x1080 --output out.mp4
```

## Available Effects

### Live Slideshows (mpv)
- **basic** - Sequential slideshow playback
- **chaos** - Shuffled slideshow playback with loop enabled
- **tile** - Live tiled grid slideshow

### Video Effects (ffmpeg)
- **ken-burns** - Smooth zoom/pan transitions
- **crossfade** - Smooth blending between images
- **glitch** - Data corruption and noise effects
- **acid** - Color shift effect
- **reality** - Distortion and transformation effects
- **kaleido** - Kaleidoscope patterns
- **matrix** - Matrix effect
- **liquid** - Liquid distortion effect

## Implementation note

Orchestration lives in Bash under [`scripts/`](scripts/) and is driven only by the Python package **`mpv_img_tricks`** (console script **`slideshow`** or **`python -m mpv_img_tricks`**). Do not rely on calling `scripts/*.sh` directly; they are backends.

Live key bindings come from [`mpv-scripts/blast.lua`](mpv-scripts/blast.lua).

## Live Controls (with `blast.lua`)

When using mpv with `--script=mpv-scripts/blast.lua`, you can control playback:

**Playback Controls:**
- **Alt+1** - Set duration to 0.001s (~1000 images/sec)
- **Alt+2** - Fast (~20 images/sec, 0.05s)
- **Alt+3** - Medium (~10 images/sec, 0.1s)
- **Alt+4** - Normal (1 image/sec, 1.0s)
- **Alt+5** - Slow (1 image/3 sec, 3.0s)
- **Alt+6** - Very slow (1 image/5 sec, 5.0s)
- **c** - Toggle shuffle
- **l** - Toggle loop playlist

**Navigation:**
- **j** - Previous image in playlist
- **k** - Next image in playlist

**Zoom Controls:**
- **Alt + =** (Alt + Equals) - Zoom in (incremental)
- **Alt + -** (Alt + Hyphen/Minus) - Zoom out (incremental)
- **Alt + z** - Jump to 1x zoom (reset)
- **Alt + x** - Jump to 2x zoom
- **Alt + v** - Jump to 3x zoom
- **Alt + Backspace** - Reset zoom and pan

**Pan Controls:**
- **Alt + Arrow Keys** - Pan image (Left/Right/Up/Down)
- **Alt + WASD** - Pan image (A=left, D=right, W=up, S=down)
- **Ctrl + Left-click + Drag** - Pan by dragging (mpv default)

**Image Management:**
- **m** - Flag current image as "keep" (writes to `keep.txt` in the same directory)
- **Shift+Delete** - Move current image to trash and skip to next

**Note:** Standard mpv keys (f for fullscreen, arrow keys, space for pause, etc.) work as usual.

## Options

### slideshow live

The subcommand name **`live`** is optional as long as you are not adding other subcommands later: **`./slideshow <images_dir_or_glob> [options]`** is equivalent. Explicit **`live`** stays the clearest form in docs and scripts.

```bash
./slideshow live <images_dir_or_glob> [options]

Playback/display:
  --duration, -d SECONDS     Duration per image
  --scale-mode MODE          fit|fill|stretch
  --instances, -n COUNT      Number of mpv instances
  --display INDEX            Target display for single instance/master
  --display-map CSV          Per-instance display mapping (e.g. 0,1)
  --master-control           Force master->follower sync
  --no-master-control        Disable master->follower sync
  --watch                    Watch for new images and add them to playlist
  --no-recursive             Disable recursive watch mode
  --shuffle                  Shuffle playlist order

Render/video:
  --render                   Render a video instead of launching live playback
  --output FILE              Output path for render mode
  --resolution SIZE          Output resolution (default: 1920x1080)
  --fps FPS                  Frames per second for effect renders
  --img-per-sec COUNT        Images per second for plain render mode

Effect-specific:
  --effect NAME              basic|chaos|tile|ken-burns|crossfade|glitch|acid|reality|kaleido|matrix|liquid
  --limit, -l COUNT          Max images for video effects
  --grid SIZE                Tile grid size
  --spacing PIXELS           Tile spacing in pixels
  --group-size COUNT         Number of images per randomized tile group
  --randomize                Randomize tile layouts
  --animate-videos           Animate video tiles instead of using still composites
  --encoder NAME             auto|hevc_videotoolbox|libx265|libx264
  --sound FILE               Play sound file during slideshow playback
  --sound-trim-db DB         Leading silence trim threshold in dB
  --max-files COUNT          Limit discovered files
  --order MODE               natural|om
  --recursive                Recurse into subdirectories
  --random-scale             Randomly alternate between fill and fit scaling

Diagnostics:
  --debug                    Print backend debug info

# full, current option list:
./slideshow live --help
```

**Watch Mode**: When enabled with `--watch`, the slideshow monitors the directory for new image files. When a new image is detected, it's automatically added to the playlist as the next item and the slideshow immediately jumps to it. Requires `fswatch` (install with `brew install fswatch` on macOS).

Current limitation: `--watch` currently supports only a single instance (`--instances 1`).

## More Examples

```bash
# Custom resolution and duration
./slideshow live ~/pics --render --effect glitch --duration 0.3 --resolution 1280x720 --output glitch.mp4

# High frame rate
./slideshow live ~/pics --render --effect reality --fps 60 --output physics-break.mp4

# Process more images
./slideshow live ~/pics --render --effect acid --limit 20 --output trip.mp4

# Short duration slideshow
./slideshow live ~/pics --duration 0.2

# Live slideshow (watches for new images)
./slideshow live ~/pics --watch

# Option-first invocation
./slideshow live ~/pics --scale-mode fill

# Live slideshow (non-recursive, current directory only)
./slideshow live ~/pics --watch --no-recursive

# Split slideshow across two displays with synchronized controls
./slideshow live ~/pics --instances 2 --display-map 0,1 --master-control

# Simple video
./slideshow live ~/pics --render --img-per-sec 30 --resolution 1920x1080 --output slideshow.mp4

# Matrix effect
./slideshow live ~/pics --render --effect matrix --output matrix-vision.mp4

# Tiled slideshow examples
./slideshow live ~/pics --effect tile --grid 2x2 --duration 3
./slideshow live ~/pics --effect tile --grid 4x1 --duration 1.5
./slideshow live ~/pics --effect tile --grid 3x2 --duration 2.5

# Randomized tiling examples
./slideshow live ~/pics --effect tile --randomize --group-size 3 --duration 2
./slideshow live ~/pics --effect tile --randomize --group-size 5 --duration 4
./slideshow live "~/videos/*.mov" --effect tile --randomize --group-size 4 --duration 1.5 --animate-videos
./slideshow live "~/videos/*.mov" --effect tile --randomize --group-size 4 --duration 1.5 --animate-videos --encoder hevc_videotoolbox
```

## Tile Effect Details

The **tile** effect creates a live slideshow that displays multiple images simultaneously in a grid layout. It uses mpv's `hstack` and `vstack` filters.

### Features:
- **Automatic screen detection** - Detects your screen resolution on macOS/Linux
- **Ultrawide support** - Works with ultrawide resolutions (for example 3440x1440, 5120x1440)
- **Live slideshow** - Images advance through the grid in real-time
- **Animated video tiles** - Optional moving video playback inside each tile (`--animate-videos`)
- **Flexible grid sizes** - Support for any grid configuration (1x3, 2x2, 3x2, etc.)
- **Randomized layouts** - Different grid layouts for each group of images
- **Group-based tiling** - Process images in customizable groups (`--group-size` as any positive integer)

### Grid Options:
- **1x3** - 3 columns x 1 row
- **2x2** - 2 columns x 2 rows
- **3x1** - 3 columns x 1 row
- **3x2** - 3 columns x 2 rows
- **4x1** - 4 columns x 1 row

### Examples:
```bash
# 3x1 grid
./slideshow live ~/pics --effect tile --grid 3x1 --duration 2

# 2x2 grid
./slideshow live ~/pics --effect tile --grid 2x2 --duration 3

# 3x2 grid
./slideshow live ~/pics --effect tile --grid 3x2 --duration 2.5

# 4x1 grid
./slideshow live ~/pics --effect tile --grid 4x1 --duration 1.5

# Randomized tiling with different layouts per group
./slideshow live ~/pics --effect tile --randomize --group-size 4 --duration 3

# Small groups with random layouts
./slideshow live ~/pics --effect tile --randomize --group-size 3 --duration 2

# Animated MOV tiles (true motion inside each grid cell)
./slideshow live "~/videos/*.mov" --effect tile --randomize --group-size 4 --duration 1.2 --animate-videos
```

### Randomized Tiling:
When using `--randomize`, each group gets a random rectangular grid selected from a dynamic layout pool where `cols * rows <= group-size`.
For example, with `--group-size 4`, layouts include combinations like `1x1`, `2x1`, `1x2`, `2x2`, `4x1`, and `1x4`.

The tile effect automatically:
- Detects your screen resolution using `system_profiler` (macOS) or `xrandr` (Linux)
- Calculates optimal tile sizes for your display
- Uses mpv's efficient `hstack`/`vstack` filters
- Advances groups continuously as a slideshow

## Scale Modes (Current)

Scale mode semantics for the slideshow CLI:
- `fit` = contain/letterbox (AR preserved)
- `fill` = cover/crop (AR preserved)
- `stretch` = fill window without preserving AR

## Future Plans

Migration sequence:

- **Phase 1 (Unified CLI) — done:** `slideshow live` is the primary interface; Bash remains the execution backend behind `mpv_img_tricks`.
- **Phase 2 (Runtime Parity)**: Port core runtime orchestration (playlist discovery, mpv/ffmpeg invocation, multi-instance controls, watch mode plumbing) to Python.
- **Phase 3 (Behavior Cleanup)**: Simplify/normalize flags during the Python move where complexity is not useful.
- **Phase 4 (Testing Expansion)**: Add smoke/integration checks for watch mode and multi-instance behavior on the Python path.
- **Phase 5 (Watch Mode Improvement)**: Add best-effort multi-instance watch routing to instance 1 (followers may not mirror new files).

## Warning
Some effects may cause seizures. Use responsibly!
