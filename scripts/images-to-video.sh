#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/images-to-video.sh <images_dir> [img_per_sec] [resolution] [output]
# Example: scripts/images-to-video.sh ~/cool-pics 60 1920x1080 out.mp4

PLAY_AFTER_RENDER="false"
PLAY_INSTANCES="1"
PLAY_DISPLAY=""
PLAY_DISPLAY_MAP=""
PLAY_MASTER_CONTROL="auto"
PLAY_SCALE_MODE="fit"
DEBUG_MODE="false"

usage() {
  cat <<'EOF'
Usage: scripts/images-to-video.sh <images_dir> [img_per_sec] [resolution] [output] [options]

Positional args:
  images_dir      Source image directory (default: .)
  img_per_sec     Frames/images per second (default: 60)
  resolution      Output resolution (default: 1920x1080)
  output          Output file path (default: flipbook.mp4)

Options:
  --play                    Preview source images via canonical mpv pipeline after render
  --instances, -n N         Number of mpv instances for --play (default: 1)
  --display INDEX           Display index for --play
  --display-map CSV         Per-instance display map for --play
  --master-control          Force master/follower sync for --play multi-instance
  --no-master-control       Disable master/follower sync for --play multi-instance
  --scale-mode MODE         Preview scaling mode for --play: fit|fill (default: fit)
  --fit                    Alias for --scale-mode fit
  --fill                   Alias for --scale-mode fill
  --debug                   Print resolved canonical runner args for --play
  --help, -h                Show this help
EOF
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --play)
      PLAY_AFTER_RENDER="true"
      shift
      ;;
    --instances|-n)
      PLAY_INSTANCES="${2:-}"
      shift 2
      ;;
    --display)
      PLAY_DISPLAY="${2:-}"
      shift 2
      ;;
    --display-map)
      PLAY_DISPLAY_MAP="${2:-}"
      shift 2
      ;;
    --scale-mode)
      PLAY_SCALE_MODE="${2:-}"
      shift 2
      ;;
    --fit)
      PLAY_SCALE_MODE="fit"
      shift
      ;;
    --fill)
      PLAY_SCALE_MODE="fill"
      shift
      ;;
    --master-control)
      PLAY_MASTER_CONTROL="true"
      shift
      ;;
    --no-master-control)
      PLAY_MASTER_CONTROL="false"
      shift
      ;;
    --debug)
      DEBUG_MODE="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

DIR="${POSITIONAL[0]:-.}"
IPS="${POSITIONAL[1]:-60}"              # images per second
RES="${POSITIONAL[2]:-1920x1080}"
OUT="${POSITIONAL[3]:-flipbook.mp4}"

if ! [[ "$PLAY_INSTANCES" =~ ^[0-9]+$ ]] || [ "$PLAY_INSTANCES" -lt 1 ]; then
  echo "Error: invalid --instances value '$PLAY_INSTANCES' (expected positive integer)" >&2
  exit 1
fi
case "$PLAY_SCALE_MODE" in
  fit|fill)
    ;;
  *)
    echo "Error: invalid --scale-mode value '$PLAY_SCALE_MODE' (expected fit or fill)" >&2
    exit 1
    ;;
esac

# Expand tilde if present
DIR="${DIR/#\~/$HOME}"

# Find images and create sorted list
TMPLIST="$(mktemp)"
find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$TMPLIST"

if [ ! -s "$TMPLIST" ]; then
  echo "Error: No images found in $DIR" >&2
  rm -f "$TMPLIST"
  exit 1
fi

COUNT=$(wc -l < "$TMPLIST")
echo "Found $COUNT images"
echo "Creating video: $OUT (${IPS} images/sec, ${RES})"

# Build concat list for stable ordering
CONCAT="$(mktemp)"
while IFS= read -r f; do
  printf "file '%s'\n" "$f" >> "$CONCAT"
done < "$TMPLIST"

# Create video using Apple VideoToolbox HEVC
if ! ffmpeg -f concat -safe 0 -i "$CONCAT" \
  -r "$IPS" \
  -vf "scale=${RES}:flags=lanczos,fps=${IPS}" \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -b:v 25M \
  -maxrate 55M \
  -bufsize 100M \
  -pix_fmt yuv420p \
  -an \
  -y "$OUT" 2>/dev/null; then
  echo "Error: Failed to create video" >&2
  rm -f "$TMPLIST" "$CONCAT"
  exit 1
fi

rm -f "$TMPLIST" "$CONCAT"
echo "✓ Video created: $OUT"
echo "Play with: mpv --fs \"$OUT\""

if [[ "$PLAY_AFTER_RENDER" == "true" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
  while [[ -L "$SCRIPT_PATH" ]]; do
    LINK_TARGET="$(readlink "$SCRIPT_PATH")"
    if [[ "$LINK_TARGET" == /* ]]; then
      SCRIPT_PATH="$LINK_TARGET"
    else
      SCRIPT_PATH="$(cd "$(dirname "$SCRIPT_PATH")" && cd "$(dirname "$LINK_TARGET")" && pwd)/$(basename "$LINK_TARGET")"
    fi
  done
  REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
  MPV_PIPELINE="${REPO_ROOT}/scripts/mpv-pipeline.sh"

  if [[ ! -x "$MPV_PIPELINE" ]]; then
    echo "Error: canonical runner not executable: $MPV_PIPELINE" >&2
    exit 1
  fi

  PLAYLIST_FILE="$(mktemp)"
  find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$PLAYLIST_FILE"
  if [[ ! -s "$PLAYLIST_FILE" ]]; then
    echo "Error: no source images available for --play preview" >&2
    rm -f "$PLAYLIST_FILE"
    exit 1
  fi

  PIPELINE_ARGS=(
    --playlist "$PLAYLIST_FILE"
    --duration "0.05"
    --fullscreen yes
    --shuffle no
    --loop-mode none
    --scale-mode "$PLAY_SCALE_MODE"
    --instances "$PLAY_INSTANCES"
    --master-control "$PLAY_MASTER_CONTROL"
    --debug "$DEBUG_MODE"
  )
  if [[ -n "$PLAY_DISPLAY" ]]; then
    PIPELINE_ARGS+=(--display "$PLAY_DISPLAY")
  fi
  if [[ -n "$PLAY_DISPLAY_MAP" ]]; then
    PIPELINE_ARGS+=(--display-map "$PLAY_DISPLAY_MAP")
  fi

  echo "Launching canonical slideshow preview..."
  "$MPV_PIPELINE" "${PIPELINE_ARGS[@]}"
  rm -f "$PLAYLIST_FILE"
fi
