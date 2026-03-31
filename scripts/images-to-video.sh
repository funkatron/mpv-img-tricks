#!/usr/bin/env bash
set -euo pipefail

# Bash backend for plain image→video render (invoked by ./slideshow live --render).
# End users: ./slideshow live <dir> --render …

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
  --scale-mode MODE         Preview scaling mode for --play: fit|fill|stretch (default: fit)
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
    --quiet|--verbose-ffmpeg)
      # Accepted from Python CLI for diagnostic parity; plain render path ignores beyond --debug.
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

require_positive_int "$PLAY_INSTANCES" "--instances" || exit 1
require_scale_mode "$PLAY_SCALE_MODE" || exit 1

# Expand tilde if present
DIR="${DIR/#\~/$HOME}"

# Find images and create sorted list
TMPLIST="$(mktemp)"
discover_images_to_playlist "$DIR" "$TMPLIST" "true"

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
  MPV_PIPELINE="$(resolve_mpv_pipeline_path "$SCRIPT_SOURCE")"

  if [[ ! -x "$MPV_PIPELINE" ]]; then
    echo "Error: canonical runner not executable: $MPV_PIPELINE" >&2
    exit 1
  fi

  PLAYLIST_FILE="$(mktemp)"
  discover_images_to_playlist "$DIR" "$PLAYLIST_FILE" "true"
  if [[ ! -s "$PLAYLIST_FILE" ]]; then
    echo "Error: no source images available for --play preview" >&2
    rm -f "$PLAYLIST_FILE"
    exit 1
  fi

  build_pipeline_common_args "0.05" "yes" "none" "$PLAY_SCALE_MODE" "$PLAY_INSTANCES" "$PLAY_MASTER_CONTROL"
  PIPELINE_ARGS=(--playlist "$PLAYLIST_FILE" --shuffle no --debug "$DEBUG_MODE" "${PIPELINE_COMMON_ARGS[@]}")
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
