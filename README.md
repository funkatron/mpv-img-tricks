# mpv-img-tricks

**⚠️ PRE-ALPHA SOFTWARE** - Experimental software in early development. Use at your own risk!

Image slideshow and effects system for building live slideshows and rendered videos from image collections.

Primary command: `./slideshow live`

This is a personal utility project. Breaking CLI changes are acceptable when they simplify the workflow.

**Defaults:** Omitted `--duration` uses **2.0** seconds per image (Python CLI default and shell backends via [`scripts/lib/constants.sh`](scripts/lib/constants.sh)). Use `--duration 0.02` (or lower) for rapid cycling.

**Advanced:** Set `MPV_IMG_TRICKS_SCRIPTS_DIR` to a directory containing `slideshow.sh`, `img-effects.sh`, and `images-to-video.sh` to override the normal `scripts/` resolution (used by unit tests and custom layouts).

## Installation

No installer is required. Run the unified CLI directly from the repo root:

- `./slideshow live` - Live slideshow entrypoint

Current shell scripts remain as internal backends for the Python CLI and are no longer the documented user interface.

Examples:
```bash
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

## Scripts

- **slideshow** - Unified CLI entrypoint
- **scripts/slideshow.sh** - Internal backend for plain live slideshow behavior
- **scripts/img-effects.sh** - Internal backend for effect execution
- **scripts/images-to-video.sh** - Internal backend for plain image-to-video rendering
- **scripts/mpv-pipeline.sh** - Canonical mpv runtime pipeline shared by scripts
- **mpv-scripts/blast.lua** - mpv script for live speed control and image management

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

Scale mode semantics for current scripts:
- `fit` = contain/letterbox (AR preserved)
- `fill` = cover/crop (AR preserved)
- `stretch` = fill window without preserving AR

## Development Testing

Run local unit tests during development:

```bash
./tests/run-unit.sh
```

## Future Plans

Migration sequence:

- **Phase 1 (Unified CLI)**: Land `slideshow live` as the primary interface while keeping shell scripts as internal execution backends.
- **Phase 2 (Runtime Parity)**: Port core runtime orchestration (playlist discovery, mpv/ffmpeg invocation, multi-instance controls, watch mode plumbing) to Python.
- **Phase 3 (Behavior Cleanup)**: Simplify/normalize flags during the Python move where complexity is not useful.
- **Phase 4 (Testing Expansion)**: Add smoke/integration checks for watch mode and multi-instance behavior on the Python path.
- **Phase 5 (Watch Mode Improvement)**: Add best-effort multi-instance watch routing to instance 1 (followers may not mirror new files).

## Warning
Some effects may cause seizures. Use responsibly!
