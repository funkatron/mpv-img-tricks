#!/bin/bash

# Image slideshow with scaling options
# Usage: ./slideshow.sh <image_dir> [options]

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_SOURCE" ]]; do
  LINK_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="${LINK_DIR}/${SCRIPT_SOURCE}"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/discovery.sh"
source "${SCRIPT_DIR}/lib/validate.sh"
source "${SCRIPT_DIR}/lib/pipeline.sh"
source "${SCRIPT_DIR}/lib/constants.sh"

# Default values
DURATION="${DEFAULT_SLIDESHOW_DURATION_SECONDS}"
DIR=""
UPSCALE_SMALLER="true"
SCALE_MODE="fit"  # fit|fill|stretch
DOWNSCALE_LARGER="true"
WATCH_MODE="false"
RECURSIVE_WATCH="true"
SHUFFLE_MODE="false"
INSTANCES="1"
DISPLAY_INDEX=""
DISPLAY_MAP=""
MASTER_CONTROL="auto"
DEBUG_MODE="false"

# Parse arguments (support both option-first and dir-first styles).
while [[ $# -gt 0 ]]; do
  case $1 in
    --duration|-d)
      DURATION="${2:-}"
      if [[ -z "$DURATION" ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
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
      SCALE_MODE="${2:-}"
      if [[ -z "$SCALE_MODE" ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
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
    --instances|-n)
      INSTANCES="${2:-}"
      if [[ -z "$INSTANCES" ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    --display)
      DISPLAY_INDEX="${2:-}"
      if [[ -z "$DISPLAY_INDEX" ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    --display-map)
      DISPLAY_MAP="${2:-}"
      if [[ -z "$DISPLAY_MAP" ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    --master-control)
      MASTER_CONTROL="true"
      shift
      ;;
    --no-master-control)
      MASTER_CONTROL="false"
      shift
      ;;
    --debug)
      DEBUG_MODE="true"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options] <image_dir>"
      echo ""
      echo "Scaling Options:"
      echo "  --upscale-smaller, -u     Upscale images smaller than window in both dimensions (default)"
      echo "  --no-upscale-smaller, -U   Don't upscale smaller images"
      echo "  --scale-mode, -s MODE     Scaling mode: fit|fill|stretch (default: fit)"
      echo "                            fit=letterbox, fill=cover/crop, stretch=legacy stretch"
      echo "  --downscale-larger, -D    Downscale images larger than window (default)"
      echo "  --no-downscale-larger      Don't downscale larger images"
      echo ""
      echo "Other Options:"
      echo "  --duration, -d SECONDS    Duration per image (default: ${DEFAULT_SLIDESHOW_DURATION_SECONDS})"
      echo "  --watch, -w               Watch for new images and add them to playlist"
      echo "  --no-recursive            Don't watch subdirectories (only with --watch)"
      echo "  --shuffle, -S             Shuffle/randomize the playlist"
      echo "  --instances, -n COUNT     Launch COUNT mpv instances with split playlists"
      echo "  --display INDEX           Target display index for single instance (or master)"
      echo "  --display-map CSV         Per-instance display mapping (e.g. 0,1,2)"
      echo "  --master-control          Force master/follower control sync for multi-instance"
      echo "  --no-master-control       Disable master/follower control sync for multi-instance"
      echo "  --debug                   Print resolved canonical runner args"
      echo ""
      echo "Examples:"
      echo "  $0 ~/pics --upscale-smaller --scale-mode fill"
      echo "  $0 --scale-mode stretch ~/pics"
      echo "  $0 ~/pics --no-downscale-larger --scale-mode fit"
      exit 0
      ;;
    *)
      if [[ "$1" == -* ]]; then
        echo "Error: unknown option '$1'" >&2
        echo "Use --help for usage information" >&2
        exit 1
      fi
      if [[ -z "$DIR" ]]; then
        DIR="$1"
        shift
      else
        echo "Error: unexpected extra argument '$1'" >&2
        echo "Usage: $0 [options] <image_dir>" >&2
        exit 1
      fi
      ;;
  esac
done

# Set default directory if omitted.
DIR="${DIR:-dead-agent-images/}"

# Expand tilde if present
DIR="${DIR/#\~/$HOME}"
require_positive_int "$INSTANCES" "--instances" || exit 1
require_scale_mode "$SCALE_MODE" || exit 1
if [[ ! -d "$DIR" ]]; then
  echo "Error: directory not found: $DIR" >&2
  exit 1
fi

echo "🎸 FLEXIBLE IMAGE BLAST"
echo "📁 Directory: $DIR"
echo "⏱️  Duration: ${DURATION}s per image"
echo "🔍 Upscale smaller: $UPSCALE_SMALLER"
echo "📐 Scale mode: $SCALE_MODE"
echo "📉 Downscale larger: $DOWNSCALE_LARGER"
echo "🧩 Instances: $INSTANCES"
if [[ -n "$DISPLAY_INDEX" ]]; then
  echo "🖥️  Display: $DISPLAY_INDEX"
fi
echo ""

# Resolve canonical runner path even when script is symlinked.
RESOLVED_SOURCE="$(resolve_script_path "$SCRIPT_SOURCE")"
MPV_PIPELINE="$(resolve_mpv_pipeline_path "$RESOLVED_SOURCE")"
if [[ ! -x "$MPV_PIPELINE" ]]; then
  echo "Error: canonical runner not executable: $MPV_PIPELINE" >&2
  exit 1
fi

# Check if directory exists
# Find images and create a temporary playlist file
TMPLIST="$(mktemp)"
discover_images_to_playlist "$DIR" "$TMPLIST" "true"

if [[ ! -s "$TMPLIST" ]]; then
  echo "Error: no images found in $DIR" >&2
  rm -f "$TMPLIST"
  exit 1
fi

COUNT=$(wc -l < "$TMPLIST")
echo "📸 Found $COUNT images"

# Set up IPC socket for watch mode
IPC_SOCKET=""
if [[ "$WATCH_MODE" == "true" ]]; then
  if [[ "$INSTANCES" != "1" ]]; then
    echo "Error: --watch currently requires --instances 1" >&2
    rm -f "$TMPLIST"
    exit 1
  fi
  IPC_SOCKET="$(mktemp -u /tmp/mpv-slideshow-XXXXXX.socket)"
  echo "👁️  Watch mode enabled (recursive: $RECURSIVE_WATCH)"
fi

echo "🚀 Starting slideshow..."
echo ""

build_pipeline_common_args "$DURATION" "yes" "playlist" "$SCALE_MODE" "$INSTANCES" "$MASTER_CONTROL"
PIPELINE_ARGS=(
  --playlist "$TMPLIST"
  "${PIPELINE_COMMON_ARGS[@]}"
  --downscale-larger "$DOWNSCALE_LARGER"
)

if [[ "$SHUFFLE_MODE" == "true" ]]; then
  PIPELINE_ARGS+=(--shuffle yes)
else
  PIPELINE_ARGS+=(--shuffle no)
fi

if [[ -n "$DISPLAY_INDEX" ]]; then
  PIPELINE_ARGS+=(--display "$DISPLAY_INDEX")
fi
if [[ -n "$DISPLAY_MAP" ]]; then
  PIPELINE_ARGS+=(--display-map "$DISPLAY_MAP")
fi
if [[ -n "$IPC_SOCKET" ]]; then
  PIPELINE_ARGS+=(--watch-ipc-socket "$IPC_SOCKET")
fi
if [[ "$DEBUG_MODE" == "true" ]]; then
  PIPELINE_ARGS+=(--debug yes)
fi

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
if ! "$MPV_PIPELINE" "${PIPELINE_ARGS[@]}" 2>/dev/null; then
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
