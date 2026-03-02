# mpv-img-tricks

**⚠️ PRE-ALPHA SOFTWARE** - Experimental software in early development. Use at your own risk!

Image slideshow and effects system for creating rapid-fire slideshows and video effects from image collections.

## Installation

The scripts are available as global commands after installation. Symlinks have been created in `~/bin`:

- `slideshow` - Image slideshow viewer
- `img-effects` - Effects and slideshow script
- `images-to-video` - Simple image-to-video converter

You can also use them directly from the scripts directory:
```bash
scripts/slideshow.sh ~/pics
scripts/img-effects.sh basic ~/pics
scripts/images-to-video.sh ~/pics 60 1920x1080 out.mp4
```

## Quick Start

### Simple Slideshows

```bash
# Basic slideshow (fast image cycling)
img-effects basic ~/pics

# Chaos mode (shuffled, infinite loop)
img-effects chaos ~/pics --duration 0.02

# Slideshow with scaling options
slideshow ~/pics
```

### Video Effects

```bash
# Ken Burns effect (smooth zoom/pan)
img-effects ken-burns ~/pics --duration 3 --output slideshow.mp4

# Visual effects (glitch, acid, reality, etc.)
img-effects glitch ~/pics --output glitch.mp4
img-effects acid ~/pics --output acid-trip.mp4
img-effects reality ~/pics --output reality-break.mp4

# Simple video from images
images-to-video ~/pics 60 1920x1080 out.mp4
```

## Available Effects

### Live Slideshows (mpv)
- **basic** - Simple fast slideshow
- **chaos** - Shuffled rapid-fire with infinite loop
- **tile** - Live tiled grid slideshow (perfect for ultrawide screens)

### Video Effects (ffmpeg)
- **ken-burns** - Smooth zoom/pan transitions
- **crossfade** - Smooth blending between images
- **glitch** - Data corruption and noise effects
- **acid** - Color shifting and morphing
- **reality** - Distortion and transformation effects
- **kaleido** - Kaleidoscope patterns
- **matrix** - Digital rain-style effects
- **liquid** - Liquid distortion morphing

## Scripts

- **scripts/img-effects.sh** - Main effects script (slideshows, tile mode, and video effects)
- **scripts/slideshow.sh** - Slideshow with image scaling options
- **scripts/images-to-video.sh** - Simple image-to-video converter
- **scripts/mpv-pipeline.sh** - Canonical mpv runtime pipeline shared by entrypoints
- **mpv-scripts/blast.lua** - mpv script for live speed control and image management

## Live Controls (with `blast.lua`)

When using mpv with `--script=mpv-scripts/blast.lua`, you can control playback:

**Playback Controls:**
- **Alt+1** - Very fast (~1000 images/sec, 0.001s)
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
- **Shift+Delete** or **Delete** - Move current image to trash and skip to next

**Note:** Standard mpv keys (f for fullscreen, arrow keys, space for pause, etc.) work as usual.

## Options

### img-effects

```bash
img-effects <effect> <image_dir> [options]
# or: scripts/img-effects.sh <effect> <image_dir> [options]

Options:
  --duration, -d SECONDS    Duration per image (default: 0.05)
  --output, -o FILE          Output file for video effects
  --resolution, -r SIZE      Output resolution (default: 1920x1080)
  --fps, -f FPS             Frames per second (default: 30)
  --scale-mode MODE         'fit' or 'fill' (default: fit)
  --fit                     Alias for --scale-mode fit
  --fill                    Alias for --scale-mode fill
  --limit, -l COUNT         Max images for video effects (default: 5)
  --instances, -n COUNT     mpv instances for live effects (basic/chaos)
  --display INDEX           Target display for single instance/master
  --display-map CSV         Per-instance display mapping (e.g. 0,1,2)
  --master-control          Enable master->follower sync for multi-instance
  --animate-videos          In tile mode, render animated .mp4 grid segments
                            (prefers HEVC VideoToolbox; falls back if unavailable)
  --encoder NAME            Animated tile encoder override:
                            auto|hevc_videotoolbox|libx265|libx264
```

### slideshow

```bash
slideshow <image_dir> [options]
# or: scripts/slideshow.sh <image_dir> [options]

Scaling Options:
  --scale-mode MODE          'fit' or 'fill' (default: fit)
  --no-upscale-smaller       Don't upscale smaller images
  --no-downscale-larger      Don't downscale larger images
  --duration SECONDS         Duration per image (default: 0.001)

Watch Mode (Live File Monitoring):
  --watch, -w                Watch for new images and add them to playlist
  --no-recursive              Don't watch subdirectories (only with --watch)

Multi-instance / Display:
  --instances, -n COUNT      Launch COUNT mpv instances (split playlists)
  --display INDEX            Target display for single instance/master
  --display-map CSV          Per-instance display mapping (e.g. 0,1)
  --master-control           Force master->follower sync in multi-instance mode
  --no-master-control        Disable sync in multi-instance mode
```

**Watch Mode**: When enabled with `--watch`, the slideshow monitors the directory for new image files. When a new image is detected, it's automatically added to the playlist as the next item and the slideshow immediately jumps to it. Requires `fswatch` (install with `brew install fswatch` on macOS).

### images-to-video

```bash
images-to-video <image_dir> [img_per_sec] [resolution] [output]
# Example: images-to-video ~/pics 60 1920x1080 out.mp4
# or: scripts/images-to-video.sh ~/pics 60 1920x1080 out.mp4

# Optional preview through canonical mpv pipeline
images-to-video ~/pics 60 1920x1080 out.mp4 --play --instances 2 --display-map 0,1 --scale-mode fill
```

## More Examples

```bash
# Custom resolution and duration
img-effects glitch ~/pics --duration 0.3 --resolution 1280x720 --output glitch.mp4

# High frame rate
img-effects reality ~/pics --fps 60 --output physics-break.mp4

# Process more images
img-effects acid ~/pics --limit 20 --output trip.mp4

# Fast slideshow
slideshow ~/pics --duration 0.001

# Live slideshow (watches for new images)
slideshow ~/pics --watch

# Live slideshow (non-recursive, current directory only)
slideshow ~/pics --watch --no-recursive

# Split slideshow across two displays with synchronized controls
slideshow ~/pics --instances 2 --display-map 0,1 --master-control

# Simple video
images-to-video ~/pics 30 1920x1080 slideshow.mp4

# Render video and then preview source images via canonical pipeline
images-to-video ~/pics 30 1920x1080 slideshow.mp4 --play --instances 2
# Matrix-style effects
scripts/img-effects.sh matrix ~/pics --output matrix-vision.mp4

# Tiled slideshow examples
scripts/img-effects.sh tile ~/pics --grid 2x2 --duration 3
scripts/img-effects.sh tile ~/pics --grid 4x1 --duration 1.5
scripts/img-effects.sh tile ~/pics --grid 3x2 --duration 2.5

# Randomized tiling examples
scripts/img-effects.sh tile ~/pics --randomize --group-size 3 --duration 2
scripts/img-effects.sh tile ~/pics --randomize --group-size 5 --duration 4
scripts/img-effects.sh tile "~/videos/*.mov" --randomize --group-size 4 --duration 1.5 --animate-videos
scripts/img-effects.sh tile "~/videos/*.mov" --randomize --group-size 4 --duration 1.5 --animate-videos --encoder hevc_videotoolbox
```

## Tile Effect Details

The **tile** effect creates a live slideshow that displays multiple images simultaneously in a grid layout. It's optimized for ultrawide screens and uses mpv's built-in `hstack` and `vstack` filters for efficient rendering.

### Features:
- **Automatic screen detection** - Detects your screen resolution for optimal tiling
- **Ultrawide optimized** - Perfect for 3440x1440, 5120x1440, and other ultrawide displays
- **Live slideshow** - Images advance through the grid in real-time
- **Animated video tiles** - Optional moving video playback inside each tile (`--animate-videos`)
- **Flexible grid sizes** - Support for any grid configuration (1x3, 2x2, 3x2, etc.)
- **Randomized layouts** - Different grid layouts for each group of images
- **Group-based tiling** - Process images in customizable groups (3-5 images per group)

### Grid Options:
- **1x3** - Horizontal strip (3 images across, 1 row)
- **2x2** - Classic 4-image grid
- **3x1** - Wide horizontal strip (3 images across)
- **3x2** - 6-image grid (3 columns, 2 rows)
- **4x1** - Ultra-wide strip (4 images across)

### Examples:
```bash
# Horizontal strip for ultrawide
scripts/img-effects.sh tile ~/pics --grid 3x1 --duration 2

# Classic 4-image grid
scripts/img-effects.sh tile ~/pics --grid 2x2 --duration 3

# Wide 6-image layout
scripts/img-effects.sh tile ~/pics --grid 3x2 --duration 2.5

# Ultra-wide strip
scripts/img-effects.sh tile ~/pics --grid 4x1 --duration 1.5

# Randomized tiling with different layouts per group
scripts/img-effects.sh tile ~/pics --randomize --group-size 4 --duration 3

# Small groups with random layouts
scripts/img-effects.sh tile ~/pics --randomize --group-size 3 --duration 2

# Animated MOV tiles (true motion inside each grid cell)
scripts/img-effects.sh tile "~/videos/*.mov" --randomize --group-size 4 --duration 1.2 --animate-videos
```

### Randomized Tiling:
When using `--randomize`, each group of images gets a random grid layout from:
- **1x1** - Single image
- **1x2** - Vertical strip (2 images)
- **2x1** - Horizontal strip (2 images)
- **1x3** - Vertical strip (3 images)
- **3x1** - Horizontal strip (3 images)
- **2x2** - Classic 4-image grid
- **1x4** - Vertical strip (4 images)
- **4x1** - Horizontal strip (4 images)
- **2x3** - 6-image grid (2 columns, 3 rows)
- **3x2** - 6-image grid (3 columns, 2 rows)

The tile effect automatically:
- Detects your screen resolution using `xrandr`
- Calculates optimal tile sizes for your display
- Uses mpv's efficient `hstack`/`vstack` filters
- Creates a seamless slideshow experience

## Development Testing

Run local unit tests during development:

```bash
./tests/run-unit.sh
```

## Future Plans

This project is currently implemented in Bash shell scripts for rapid prototyping. Future development plans include:

- **Python Rewrite**: Rewrite in Python for better maintainability and cross-platform compatibility
- **Enhanced Effects**: More sophisticated visual effects using libraries like OpenCV and PIL
- **Real-time Processing**: Live effects processing without pre-rendering
- **GUI Interface**: Optional graphical interface for effect configuration
- **Plugin System**: Modular architecture for custom effects
- **Performance Optimization**: GPU acceleration and multi-threading support

## Warning
Some effects may cause seizures. Use responsibly!
