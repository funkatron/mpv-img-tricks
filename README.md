# mpv-img-tricks

Flexible image slideshow and effects system with scaling control and extreme visual experiments.

## Quick Start

```bash
# Flexible slideshow with scaling control
scripts/flexible-blast.sh ~/pics

# Basic slideshow (like original blast.sh)
scripts/img-effects.sh basic ~/pics

# Chaos mode (shuffled rapid-fire)
scripts/img-effects.sh chaos ~/pics --duration 0.02

# Ken Burns effect video
scripts/img-effects.sh ken-burns ~/pics --duration 3 --output slideshow.mp4

# Psychedelic acid trip
scripts/img-effects.sh acid ~/pics --output acid-trip.mp4

# Reality-breaking physics effects
scripts/img-effects.sh reality ~/pics --output reality-break.mp4
```

## Effects

### Basic Effects
- **basic** - Simple slideshow (like original blast.sh)
- **chaos** - Shuffled rapid-fire with infinite loop
- **ken-burns** - Smooth zoom/pan transitions
- **crossfade** - Smooth blending between images

### Extreme Effects
- **glitch** - Datamosh-style corruption and noise
- **acid** - Psychedelic color shifting and morphing
- **reality** - Physics-breaking impossible effects
- **kaleido** - Kaleidoscope patterns and fractals
- **matrix** - Matrix rain and digital effects
- **liquid** - Liquid distortion and morphing

## Scripts

- **scripts/flexible-blast.sh** - Flexible slideshow with scaling control (upscale/downscale/fit/fill)
- **scripts/img-effects.sh** - Unified effects system (basic/chaos/extreme effects)
- **scripts/make-video.sh** - Stitch images to video (smooth timing)
- **mpv-scripts/blast.lua** - Hotkeys to change speed live

## Hotkeys (when mpv loads `blast.lua`)
- **1** : ~60 img/s   (0.016s/image)
- **2** : ~20 img/s   (0.05s/image)
- **3** : ~10 img/s   (0.1s/image)
- **c** : toggle shuffle
- **l** : toggle loop-playlist

## Flexible Slideshow Options

The `flexible-blast.sh` script gives you control over image scaling:

```bash
# Default behavior (upscale smaller, fit mode, downscale larger)
scripts/flexible-blast.sh ~/pics

# Fill the window (crop to fit)
scripts/flexible-blast.sh ~/pics --scale-mode fill

# Don't upscale smaller images
scripts/flexible-blast.sh ~/pics --no-upscale-smaller

# Don't downscale larger images
scripts/flexible-blast.sh ~/pics --no-downscale-larger

# Custom duration
scripts/flexible-blast.sh ~/pics --duration 0.005
```

### Scaling Options:
- **--upscale-smaller** / **--no-upscale-smaller** - Whether to upscale images smaller than window (default: upscale)
- **--scale-mode** - `fit` (maintain aspect ratio) or `fill` (crop to fill window) (default: fit)
- **--downscale-larger** / **--no-downscale-larger** - Whether to downscale larger images (default: downscale)

## Examples

```bash
# Create a glitch art video
scripts/img-effects.sh glitch ~/cool-pics --duration 0.3 --output glitch-art.mp4

# Acid trip with custom resolution
scripts/img-effects.sh acid ~/pics --resolution 1280x720 --output trip.mp4

# Reality-breaking effects at 60fps
scripts/img-effects.sh reality ~/pics --fps 60 --output physics-break.mp4

# Matrix-style effects
scripts/img-effects.sh matrix ~/pics --output matrix-vision.mp4
```

## Warning
Some effects may cause seizures or reality distortion. Use responsibly!
