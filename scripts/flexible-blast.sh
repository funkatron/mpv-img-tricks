#!/bin/bash

# Flexible image slideshow with scaling options
# Usage: ./flexible-blast.sh <image_dir> [options]

# Default values
DURATION="0.001"
DIR="${1:-dead-agent-images/}"
UPSCALE_SMALLER="true"
SCALE_MODE="fit"  # fit or fill
DOWNSCALE_LARGER="true"

# Parse arguments
shift  # Remove directory from arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --duration|-d)
      DURATION="$2"
      shift 2
      ;;
    --upscale-smaller|-u)
      UPSCALE_SMALLER="true"
      shift
      ;;
    --no-upscale-smaller|-U)
      UPSCALE_SMALLER="false"
      shift
      ;;
    --scale-mode|-s)
      SCALE_MODE="$2"
      shift 2
      ;;
    --downscale-larger|-D)
      DOWNSCALE_LARGER="true"
      shift
      ;;
    --no-downscale-larger|-d)
      DOWNSCALE_LARGER="false"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 <image_dir> [options]"
      echo ""
      echo "Scaling Options:"
      echo "  --upscale-smaller, -u     Upscale images smaller than window in both dimensions (default)"
      echo "  --no-upscale-smaller, -U   Don't upscale smaller images"
      echo "  --scale-mode, -s MODE     Set scaling mode: 'fit' or 'fill' (default: fit)"
      echo "  --downscale-larger, -D    Downscale images larger than window (default)"
      echo "  --no-downscale-larger, -d Don't downscale larger images"
      echo ""
      echo "Other Options:"
      echo "  --duration, -d SECONDS    Duration per image (default: 0.001)"
      echo ""
      echo "Examples:"
      echo "  $0 ~/pics --upscale-smaller --scale-mode fill"
      echo "  $0 ~/pics --no-downscale-larger --scale-mode fit"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Expand tilde if present
DIR="${DIR/#\~/$HOME}"

echo "🎸 FLEXIBLE IMAGE BLAST"
echo "📁 Directory: $DIR"
echo "⏱️  Duration: ${DURATION}s per image"
echo "🔍 Upscale smaller: $UPSCALE_SMALLER"
echo "📐 Scale mode: $SCALE_MODE"
echo "📉 Downscale larger: $DOWNSCALE_LARGER"
echo ""

# Build mpv options
MPV_OPTS="--image-display-duration=${DURATION} --fullscreen --loop-playlist=inf --no-audio"

# Handle scaling options
if [[ "$SCALE_MODE" == "fill" ]]; then
  MPV_OPTS="${MPV_OPTS} --no-keepaspect-window"
else
  MPV_OPTS="${MPV_OPTS} --keepaspect-window"
fi

# Handle upscaling smaller images
if [[ "$UPSCALE_SMALLER" == "true" ]]; then
  MPV_OPTS="${MPV_OPTS} --video-scale-x=2 --video-scale-y=2"
fi

# Handle downscaling larger images
if [[ "$DOWNSCALE_LARGER" == "false" ]]; then
  MPV_OPTS="${MPV_OPTS} --no-keepaspect-window"
fi

# Check if directory exists
if [[ ! -d "$DIR" ]]; then
  echo "❌ Directory not found: $DIR"
  exit 1
fi

# Find images and create a temporary playlist file
TMPLIST="$(mktemp)"
find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort -V > "$TMPLIST"

if [[ ! -s "$TMPLIST" ]]; then
  echo "❌ No images found in $DIR"
  rm -f "$TMPLIST"
  exit 1
fi

COUNT=$(wc -l < "$TMPLIST")
echo "📸 Found $COUNT images"
echo "🚀 Starting slideshow..."
echo ""

# Run the slideshow using the playlist file
mpv ${MPV_OPTS} --playlist="$TMPLIST"

# Clean up
rm -f "$TMPLIST"
