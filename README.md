# mpv-img-tricks

**⚠️ PRE-ALPHA SOFTWARE** - Experimental software in early development. Use at your own risk!

Image slideshow and effects system for creating rapid-fire slideshows and video effects from image collections.

## Installation

The scripts are available as global commands after installation. Symlinks have been created in `~/bin`:

- `slideshow` - Image slideshow viewer
- `image-effects` - Effects and slideshow script
- `images-to-video` - Simple image-to-video converter

You can also use them directly from the scripts directory:
```bash
scripts/slideshow.sh ~/pics
scripts/image-effects.sh basic ~/pics
scripts/images-to-video.sh ~/pics 60 1920x1080 out.mp4
```

## Quick Start

### Simple Slideshows

```bash
# Basic slideshow (fast image cycling)
image-effects basic ~/pics

# Chaos mode (shuffled, infinite loop)
image-effects chaos ~/pics --duration 0.02

# Slideshow with scaling options
slideshow ~/pics
```

### Video Effects

```bash
# Ken Burns effect (smooth zoom/pan)
image-effects ken-burns ~/pics --duration 3 --output slideshow.mp4

# Visual effects (glitch, acid, reality, etc.)
image-effects glitch ~/pics --output glitch.mp4
image-effects acid ~/pics --output acid-trip.mp4
image-effects reality ~/pics --output reality-break.mp4

# Simple video from images
images-to-video ~/pics 60 1920x1080 out.mp4
```

## Available Effects

### Live Slideshows (mpv)
- **basic** - Simple fast slideshow
- **chaos** - Shuffled rapid-fire with infinite loop

### Video Effects (ffmpeg)
- **ken-burns** - Smooth zoom/pan transitions
- **crossfade** - Smooth blending between images
- **glitch** - Color distortion and corruption effects
- **acid** - Psychedelic color shifting
- **reality** - Distortion and transformation effects
- **kaleido** - Kaleidoscope patterns
- **matrix** - Digital rain-style effects
- **liquid** - Liquid distortion morphing

## Scripts

- **scripts/image-effects.sh** - Main effects script (slideshows and video effects)
- **scripts/slideshow.sh** - Slideshow with image scaling options
- **scripts/images-to-video.sh** - Simple image-to-video converter
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

### image-effects

```bash
image-effects <effect> <image_dir> [options]
# or: scripts/image-effects.sh <effect> <image_dir> [options]

Options:
  --duration, -d SECONDS    Duration per image (default: 0.05)
  --output, -o FILE          Output file for video effects
  --resolution, -r SIZE      Output resolution (default: 1920x1080)
  --fps, -f FPS             Frames per second (default: 30)
  --limit, -l COUNT         Max images for video effects (default: 5)
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
```

**Watch Mode**: When enabled with `--watch`, the slideshow monitors the directory for new image files. When a new image is detected, it's automatically added to the playlist as the next item and the slideshow immediately jumps to it. Requires `fswatch` (install with `brew install fswatch` on macOS).

### images-to-video

```bash
images-to-video <image_dir> [img_per_sec] [resolution] [output]
# Example: images-to-video ~/pics 60 1920x1080 out.mp4
# or: scripts/images-to-video.sh ~/pics 60 1920x1080 out.mp4
```

## More Examples

```bash
# Custom resolution and duration
image-effects glitch ~/pics --duration 0.3 --resolution 1280x720 --output glitch.mp4

# High frame rate
image-effects reality ~/pics --fps 60 --output physics-break.mp4

# Process more images
image-effects acid ~/pics --limit 20 --output trip.mp4

# Fast slideshow
slideshow ~/pics --duration 0.001

# Live slideshow (watches for new images)
slideshow ~/pics --watch

# Live slideshow (non-recursive, current directory only)
slideshow ~/pics --watch --no-recursive

# Simple video
images-to-video ~/pics 30 1920x1080 slideshow.mp4
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
