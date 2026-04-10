#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# Bash backend for plain image→video render (invoked by ./slideshow live --render).
# End users: ./slideshow live <sources...> --render …

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

IMG_PER_SEC="60"
RESOLUTION="1920x1080"
OUTPUT="flipbook.mp4"
POSITIONAL=()

usage() {
  cat <<'EOF'
Usage: scripts/images-to-video.sh [options] [SOURCE ...]

Sources:
  SOURCE          One or more image directories, files, or globs (default: .)

Options:
  --img-per-sec N   Frames/images per second (default: 60)
  --resolution WxH  Output resolution (default: 1920x1080)
  --output, -o PATH Output file path (default: flipbook.mp4)
  --play              Preview source images via canonical mpv pipeline after render
  --instances, -n N   Number of mpv instances for --play (default: 1)
  --display INDEX     Display index for --play
  --display-map CSV   Per-instance display map for --play
  --master-control    Force master/follower sync for --play multi-instance
  --no-master-control Disable master/follower sync for --play multi-instance
  --scale-mode MODE   Preview scaling mode for --play: fit|fill|stretch (default: fit)
  --fit               Alias for --scale-mode fit
  --fill              Alias for --scale-mode fill
  --debug             Print resolved canonical runner args for --play
  --help, -h          Show this help

Legacy (no --img-per-sec/--resolution/--output):
  images-to-video.sh <dir> <img_per_sec> <resolution> <output>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --img-per-sec)
      IMG_PER_SEC="${2:?}"
      shift 2
      ;;
    --resolution)
      RESOLUTION="${2:?}"
      shift 2
      ;;
    --output|-o)
      OUTPUT="${2:?}"
      shift 2
      ;;
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

# Legacy: <dir> <ips> <res> <out> when four positionals match numeric + resolution pattern
SOURCES=()
if [[ ${#POSITIONAL[@]} -eq 4 ]] \
  && [[ "${POSITIONAL[1]}" =~ ^[0-9]+$ ]] \
  && [[ "${POSITIONAL[2]}" =~ ^[0-9]+x[0-9]+$ ]]; then
  SOURCES=("${POSITIONAL[0]}")
  IMG_PER_SEC="${POSITIONAL[1]}"
  RESOLUTION="${POSITIONAL[2]}"
  OUTPUT="${POSITIONAL[3]}"
elif [[ ${#POSITIONAL[@]} -ge 1 ]]; then
  SOURCES=("${POSITIONAL[@]}")
else
  SOURCES=(.)
fi

for i in "${!SOURCES[@]}"; do
  SOURCES[i]="${SOURCES[$i]/#\~/$HOME}"
done

require_positive_int "$PLAY_INSTANCES" "--instances" || exit 1
require_scale_mode "$PLAY_SCALE_MODE" || exit 1

# Find images and create sorted list (recursive discovery, natural order)
TMPLIST="$(mktemp)"
mpv_img_tricks_discover_sources_to_playlist "$TMPLIST" "natural" "true" "${SOURCES[@]}"

if [ ! -s "$TMPLIST" ]; then
  echo "Error: No images found for sources: ${SOURCES[*]}" >&2
  rm -f "$TMPLIST"
  exit 1
fi

COUNT=$(wc -l < "$TMPLIST")
echo "Found $COUNT images"
echo "Creating video: $OUTPUT (${IMG_PER_SEC} images/sec, ${RESOLUTION})"

# Build concat list for stable ordering
CONCAT="$(mktemp)"
while IFS= read -r f; do
  printf "file '%s'\n" "$f" >> "$CONCAT"
done <"$TMPLIST"

# Create video using Apple VideoToolbox HEVC
if ! ffmpeg -f concat -safe 0 -i "$CONCAT" \
  -r "$IMG_PER_SEC" \
  -vf "scale=${RESOLUTION}:flags=lanczos,fps=${IMG_PER_SEC}" \
  -c:v hevc_videotoolbox \
  -tag:v hvc1 \
  -b:v 25M \
  -maxrate 55M \
  -bufsize 100M \
  -pix_fmt yuv420p \
  -an \
  -y "$OUTPUT" 2>/dev/null; then
  echo "Error: Failed to create video" >&2
  rm -f "$TMPLIST" "$CONCAT"
  exit 1
fi

rm -f "$TMPLIST" "$CONCAT"
echo "✓ Video created: $OUTPUT"
echo "Play with: mpv --fs \"$OUTPUT\""

if [[ "$PLAY_AFTER_RENDER" == "true" ]]; then
  MPV_PIPELINE="$(resolve_mpv_pipeline_path "$SCRIPT_SOURCE")"

  if [[ ! -x "$MPV_PIPELINE" ]]; then
    echo "Error: canonical runner not executable: $MPV_PIPELINE" >&2
    exit 1
  fi

  PLAYLIST_FILE="$(mktemp)"
  mpv_img_tricks_discover_sources_to_playlist "$PLAYLIST_FILE" "natural" "true" "${SOURCES[@]}"
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
