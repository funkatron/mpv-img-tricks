#!/bin/bash

# Image slideshow with scaling options
# Usage: ./slideshow.sh <image_dir> [options]

# Default values
DURATION="0.001"
DIR="${1:-dead-agent-images/}"
UPSCALE_SMALLER="true"
SCALE_MODE="fit"  # fit or fill
DOWNSCALE_LARGER="true"
WATCH_MODE="false"
RECURSIVE_WATCH="true"
SHUFFLE_MODE="false"

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
    --no-downscale-larger)
      DOWNSCALE_LARGER="false"
      shift
      ;;
    --watch|-w)
      WATCH_MODE="true"
      shift
      ;;
    --no-recursive)
      RECURSIVE_WATCH="false"
      shift
      ;;
    --shuffle|-S)
      SHUFFLE_MODE="true"
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
      echo "  --no-downscale-larger      Don't downscale larger images"
      echo ""
      echo "Other Options:"
      echo "  --duration, -d SECONDS    Duration per image (default: 0.001)"
      echo "  --watch, -w               Watch for new images and add them to playlist"
      echo "  --no-recursive            Don't watch subdirectories (only with --watch)"
      echo "  --shuffle, -S             Shuffle/randomize the playlist"
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
# Resolve script path even when called via symlink
SCRIPT_PATH="$0"
if [[ -L "$SCRIPT_PATH" ]]; then
  # If called via symlink, resolve to actual script location
  LINK_TARGET="$(readlink "$SCRIPT_PATH")"
  if [[ "$LINK_TARGET" == /* ]]; then
    # Absolute symlink
    SCRIPT_PATH="$LINK_TARGET"
  else
    # Relative symlink - resolve relative to symlink location
    SCRIPT_PATH="$(cd "$(dirname "$SCRIPT_PATH")" && cd "$(dirname "$LINK_TARGET")" && pwd)/$(basename "$LINK_TARGET")"
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
LUA_SCRIPT="${SCRIPT_DIR}/mpv-scripts/blast.lua"

# Add shuffle option if requested
if [[ "$SHUFFLE_MODE" == "true" ]]; then
  SHUFFLE_OPT="--shuffle"
else
  SHUFFLE_OPT=""
fi

# Verify Lua script exists
if [[ ! -f "$LUA_SCRIPT" ]]; then
  echo "⚠️  Warning: Lua script not found at $LUA_SCRIPT" >&2
  echo "   Key bindings will not be available." >&2
  MPV_OPTS="--image-display-duration=${DURATION} --fullscreen --loop-playlist=inf --no-audio ${SHUFFLE_OPT}"
else
  MPV_OPTS="--image-display-duration=${DURATION} --fullscreen --loop-playlist=inf --no-audio ${SHUFFLE_OPT} --script=${LUA_SCRIPT}"
fi

# Default: mpv automatically scales images to fit window while maintaining aspect ratio
# Handle scaling mode
if [[ "$SCALE_MODE" == "fill" ]]; then
  # Fill mode: stretch to fill window (may distort aspect ratio)
  MPV_OPTS="${MPV_OPTS} --no-keepaspect"
else
  # Fit mode: maintain aspect ratio, scale to fit window (default behavior)
  MPV_OPTS="${MPV_OPTS} --keepaspect"
fi

# Handle upscaling smaller images
if [[ "$UPSCALE_SMALLER" == "true" ]]; then
  # Upscale smaller images: mpv does this by default with --keepaspect
  # No special option needed
  :
else
  # Don't upscale: this would require disabling autofit, but mpv always scales to fit
  # This option is less useful with mpv's default behavior
  :
fi

# Handle downscaling larger images
if [[ "$DOWNSCALE_LARGER" == "false" ]]; then
  # Don't downscale: show at original size (will be cropped if larger than window)
  # Disable window aspect ratio locking to allow showing full image
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

# Set up IPC socket for watch mode
IPC_SOCKET=""
if [[ "$WATCH_MODE" == "true" ]]; then
  IPC_SOCKET="$(mktemp -u /tmp/mpv-slideshow-XXXXXX.socket)"
  MPV_OPTS="${MPV_OPTS} --input-ipc-server=${IPC_SOCKET}"
  echo "👁️  Watch mode enabled (recursive: $RECURSIVE_WATCH)"
fi

echo "🚀 Starting slideshow..."
echo ""

# Function to send JSON command to mpv IPC
send_mpv_command() {
  local cmd="$1"
  if [[ -n "$IPC_SOCKET" && -S "$IPC_SOCKET" ]]; then
    # Try different methods to send IPC commands
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import socket
import sys
import json
try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect('$IPC_SOCKET')
    sock.send(('$cmd' + '\n').encode())
    response = sock.recv(4096).decode()
    sock.close()
    print(response, end='')
except:
    pass
" 2>/dev/null || true
    elif command -v nc >/dev/null 2>&1; then
      echo "$cmd" | nc -U "$IPC_SOCKET" 2>/dev/null || true
    else
      # Fallback: try direct socket write (may not work on all systems)
      echo "$cmd" > "$IPC_SOCKET" 2>/dev/null || true
    fi
  fi
}

# Function to add new image to playlist and seek to it
add_and_seek_to_image() {
  local image_path="$1"
  if [[ ! -f "$image_path" ]]; then
    return
  fi

  # Check if it's an image file
  case "$image_path" in
    *.jpg|*.jpeg|*.JPG|*.JPEG|*.png|*.PNG|*.webp|*.WEBP)
      # Escape the path for JSON
      local escaped_path
      escaped_path=$(printf '%s' "$image_path" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo "\"$image_path\"")

      # Get current playlist position
      local current_pos
      current_pos=$(send_mpv_command '{"command": ["get_property", "playlist-pos"]}' 2>/dev/null | grep -o '"data":[0-9]*' | grep -o '[0-9]*' || echo "0")

      # Add file to playlist (append after current position)
      send_mpv_command "{\"command\": [\"loadfile\", $escaped_path, \"append-play\"]}" >/dev/null 2>&1

      # Wait a moment for file to be added
      sleep 0.2

      # Calculate target position (next after current)
      local target_pos=$((current_pos + 1))

      # Seek to the new item
      send_mpv_command "{\"command\": [\"set_property\", \"playlist-pos\", $target_pos]}" >/dev/null 2>&1

      echo "➕ Added and jumped to: $(basename "$image_path")"
      ;;
  esac
}

# Start file watcher in background if watch mode is enabled
WATCHER_PID=""
if [[ "$WATCH_MODE" == "true" ]]; then
  # Check if fswatch is available
  if ! command -v fswatch >/dev/null 2>&1; then
    echo "⚠️  Warning: fswatch not found. Install with: brew install fswatch" >&2
    echo "   Watch mode disabled." >&2
    WATCH_MODE="false"
  else
    # Track seen files to avoid duplicates
    SEEN_FILES="$(mktemp)"
    cat "$TMPLIST" > "$SEEN_FILES"

    # Start fswatch in background to monitor for new files
    (
      while true; do
        if [[ "$RECURSIVE_WATCH" == "true" ]]; then
          fswatch -1 -r -e ".*" -i "\\.(jpg|jpeg|png|webp)$" "$DIR" 2>/dev/null | while read -r newfile; do
            # Small delay to ensure file is fully written
            sleep 0.2
            if [[ -f "$newfile" ]] && ! grep -Fxq "$newfile" "$SEEN_FILES" 2>/dev/null; then
              echo "$newfile" >> "$SEEN_FILES"
              add_and_seek_to_image "$newfile"
            fi
          done
        else
          fswatch -1 -e ".*" -i "\\.(jpg|jpeg|png|webp)$" "$DIR" 2>/dev/null | while read -r newfile; do
            sleep 0.2
            if [[ -f "$newfile" ]] && ! grep -Fxq "$newfile" "$SEEN_FILES" 2>/dev/null; then
              echo "$newfile" >> "$SEEN_FILES"
              add_and_seek_to_image "$newfile"
            fi
          done
        fi
      done
    ) &
    WATCHER_PID=$!
  fi
fi

# Run the slideshow using the playlist file
if ! mpv ${MPV_OPTS} --playlist="$TMPLIST" 2>/dev/null; then
  echo "Error: Failed to start slideshow" >&2
  # Clean up watcher if running
  if [[ -n "$WATCHER_PID" ]]; then
    kill "$WATCHER_PID" 2>/dev/null || true
  fi
  rm -f "$TMPLIST" "$IPC_SOCKET" "$SEEN_FILES"
  exit 1
fi

# Clean up
if [[ -n "$WATCHER_PID" ]]; then
  kill "$WATCHER_PID" 2>/dev/null || true
fi
rm -f "$TMPLIST" "$IPC_SOCKET" "$SEEN_FILES"
