#!/usr/bin/env bash
set -euo pipefail

# mpv-img-tricks: Unified script with modular effects
# Usage: img-effects <effect> <images_dir> [options]
#    or: scripts/img-effects.sh <effect> <images_dir> [options]
#
# Effects:
#   basic     - Simple slideshow (like original blast.sh)
#   chaos     - Shuffled rapid-fire (like blast-chaos.sh)
#   ken-burns - Smooth zoom/pan transitions
#   crossfade - Smooth blending between images
#   glitch    - Datamosh-style corruption effects
#   acid      - Psychedelic color shifting
#   reality   - Physics-breaking impossible effects
#   kaleido   - Kaleidoscope patterns
#   matrix    - Matrix rain effects
#   liquid    - Liquid distortion morphing
#   tile      - Tile small groups of images in a grid
#
# Examples:
#   img-effects basic ~/pics
#   img-effects chaos ~/pics --duration 0.02
#   img-effects ken-burns ~/pics --duration 3 --output slideshow.mp4
#   img-effects acid ~/pics --resolution 1920x1080
#   img-effects tile ~/pics --grid 2x2 --spacing 12

# Default values
EFFECT="${1:-basic}"
DURATION="0.05"
OUTPUT=""
RESOLUTION="1920x1080"
FPS="30"
LIMIT="5"  # Default limit for video effects
SCALE_MODE="fit"  # fit|fill scaling behavior for mpv/tile paths
GRID="2x2"  # Default grid size for tile effect
SPACING="0"  # Pixel gap between tiles in tile effect
GROUP_SIZE="4"  # Number of images per group for randomization
RANDOMIZE="false"  # Whether to randomize grid layouts
RECURSIVE="false"  # Whether to recurse into subdirectories
USE_PLAYLIST="false"  # Whether to use playlist file for large image sets
RANDOM_SCALE="false"  # Whether to randomly alternate between fill and fit scaling
CACHE_COMPOSITES="true"  # Cache randomized tile composites by default
CACHE_VERSION="v3"  # Bump when randomized composite behavior changes
JOBS="auto"  # Parallel jobs for randomized tile compositing
DEBUG="false"  # Enable shell tracing and raw tool output
SOUND_FILE=""  # Optional sound file during slideshow playback
SOUND_TRIM_DB="-45"  # Leading silence trim threshold in dB
MAX_FILES=""  # Optional cap on discovered images
FILE_ORDER="natural"  # natural (sort -V) or om (oldest mtime first)
FFMPEG_MEM_ARGS="-threads 1 -filter_threads 1 -filter_complex_threads 1"  # Keep ffmpeg memory usage predictable
BACKGROUND_AUDIO_PID=""  # Background mpv PID for continuous tile audio
PREPARED_SOUND_FILE=""  # Resolved/processed sound file path used at runtime
TEMP_SOUND_FILE=""  # Temp trimmed sound file for cleanup
TMPLIST=""  # Temp list file used during image discovery
TILE_SKIP_LOG=""  # Log of unreadable tile inputs that were skipped
MPV_INSTANCES="1"  # Number of mpv instances for live slideshow effects
DISPLAY_INDEX=""  # Preferred display index for single instance or master
DISPLAY_MAP=""  # Per-instance display mapping CSV
MASTER_CONTROL_MODE="auto"  # yes|no|auto for multi-instance sync
RANDOM_SCALE_LUA_SCRIPT=""  # Temp lua script for random fit/crop mode
TILE_VIDEO_SEEK="0.25"  # Seek offset (seconds) when sampling video frames for tile composites
ANIMATE_VIDEOS="false"  # Render animated tile composites instead of still snapshots
TILE_VIDEO_ENCODER_OVERRIDE="auto"  # auto|hevc_videotoolbox|libx265|libx264
TILE_VIDEO_ENCODER_READY="false"  # Whether animated tile encoder preference was initialized
TILE_VIDEO_ENCODER_NAME=""  # Selected encoder name for animated tile composites
TILE_VIDEO_CODEC_ARGS=()  # ffmpeg codec args for animated tile composites

# Parse command line arguments
shift  # Remove effect from arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --duration|-d)
      if [[ "$1" == *"="* ]]; then
        DURATION="${1#*=}"
        shift
      else
        DURATION="$2"
        shift 2
      fi
      ;;
    --output|-o)
      if [[ "$1" == *"="* ]]; then
        OUTPUT="${1#*=}"
        shift
      else
        OUTPUT="$2"
        shift 2
      fi
      ;;
    --resolution|-r)
      if [[ "$1" == *"="* ]]; then
        RESOLUTION="${1#*=}"
        shift
      else
        RESOLUTION="$2"
        shift 2
      fi
      ;;
    --fps|-f)
      if [[ "$1" == *"="* ]]; then
        FPS="${1#*=}"
        shift
      else
        FPS="$2"
        shift 2
      fi
      ;;
    --scale-mode)
      if [[ "$1" == *"="* ]]; then
        SCALE_MODE="${1#*=}"
        shift
      else
        SCALE_MODE="$2"
        shift 2
      fi
      ;;
    --fit)
      SCALE_MODE="fit"
      shift
      ;;
    --fill)
      SCALE_MODE="fill"
      shift
      ;;
    --limit|-l)
      if [[ "$1" == *"="* ]]; then
        LIMIT="${1#*=}"
        shift
      else
        LIMIT="$2"
        shift 2
      fi
      ;;
    --grid|-g)
      if [[ "$1" == *"="* ]]; then
        GRID="${1#*=}"
        shift
      else
        GRID="$2"
        shift 2
      fi
      ;;
    --spacing|-s)
      if [[ "$1" == *"="* ]]; then
        SPACING="${1#*=}"
        shift
      else
        SPACING="$2"
        shift 2
      fi
      ;;
    --group-size|-gs)
      if [[ "$1" == *"="* ]]; then
        GROUP_SIZE="${1#*=}"
        shift
      else
        GROUP_SIZE="$2"
        shift 2
      fi
      ;;
    --jobs|-j)
      if [[ "$1" == *"="* ]]; then
        JOBS="${1#*=}"
        shift
      else
        JOBS="$2"
        shift 2
      fi
      ;;
    --sound|-S)
      if [[ "$1" == *"="* ]]; then
        SOUND_FILE="${1#*=}"
        shift
      else
        SOUND_FILE="$2"
        shift 2
      fi
      ;;
    --sound-trim-db)
      if [[ "$1" == *"="* ]]; then
        SOUND_TRIM_DB="${1#*=}"
        shift
      else
        SOUND_TRIM_DB="$2"
        shift 2
      fi
      ;;
    --max-files|-N)
      if [[ "$1" == *"="* ]]; then
        MAX_FILES="${1#*=}"
        shift
      else
        MAX_FILES="$2"
        shift 2
      fi
      ;;
    --order)
      if [[ "$1" == *"="* ]]; then
        FILE_ORDER="${1#*=}"
        shift
      else
        FILE_ORDER="$2"
        shift 2
      fi
      ;;
    --debug)
      DEBUG="true"
      shift
      ;;
    --instances|-n)
      if [[ "$1" == *"="* ]]; then
        MPV_INSTANCES="${1#*=}"
        shift
      else
        MPV_INSTANCES="$2"
        shift 2
      fi
      ;;
    --display)
      if [[ "$1" == *"="* ]]; then
        DISPLAY_INDEX="${1#*=}"
        shift
      else
        DISPLAY_INDEX="$2"
        shift 2
      fi
      ;;
    --display-map)
      if [[ "$1" == *"="* ]]; then
        DISPLAY_MAP="${1#*=}"
        shift
      else
        DISPLAY_MAP="$2"
        shift 2
      fi
      ;;
    --master-control)
      MASTER_CONTROL_MODE="yes"
      shift
      ;;
    --no-master-control)
      MASTER_CONTROL_MODE="no"
      shift
      ;;
    --randomize|-z)
      RANDOMIZE="true"
      shift
      ;;
    --animate-videos|--animate-video)
      ANIMATE_VIDEOS="true"
      shift
      ;;
    --encoder)
      if [[ "$1" == *"="* ]]; then
        TILE_VIDEO_ENCODER_OVERRIDE="${1#*=}"
        shift
      else
        TILE_VIDEO_ENCODER_OVERRIDE="$2"
        shift 2
      fi
      ;;
    --no-animate-videos|--no-animate-video)
      ANIMATE_VIDEOS="false"
      shift
      ;;
    --no-cache)
      CACHE_COMPOSITES="false"
      shift
      ;;
    --recursive|-R)
      RECURSIVE="true"
      shift
      ;;
    --playlist|-p)
      USE_PLAYLIST="true"
      shift
      ;;
    --random-scale|-rs)
      RANDOM_SCALE="true"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 <effect> <images_dir_or_glob> [options]"
      echo "Effects: basic, chaos, ken-burns, crossfade, glitch, acid, reality, kaleido, matrix, liquid, tile"
      echo "Options:"
      echo "  --duration, -d    Duration per image (default: 0.05)"
      echo "  --output, -o      Output file for video effects"
      echo "  --resolution, -r  Output resolution (default: 1920x1080)"
      echo "  --fps, -f        Frames per second (default: 30)"
      echo "  --scale-mode MODE  Image scaling mode: fit or fill (default: fit)"
      echo "  --fit              Alias for --scale-mode fit"
      echo "  --fill             Alias for --scale-mode fill"
      echo "  --limit, -l      Max images for video effects (default: 5)"
      echo "  --grid, -g       Grid size for tile effect (default: 2x2)"
      echo "  --spacing, -s N  Tile spacing in pixels (default: 0)"
      echo "  --group-size, -gs  Number of images per group for randomization (default: 4)"
      echo "  --jobs, -j N       Parallel render jobs for randomized tile (default: auto)"
      echo "  --sound, -S FILE   Play sound file during slideshow playback"
      echo "  --sound-trim-db N  Leading silence trim threshold in dB (default: -45)"
      echo "  --max-files, -N N  Use only the first N discovered files"
      echo "  --order MODE       File ordering: natural (default) or om (oldest mtime first)"
      echo "  --debug            Enable shell trace and raw tool output"
      echo "  --instances, -n N  Launch N mpv instances for live slideshow effects"
      echo "  --display INDEX    Target display index for single instance/master"
      echo "  --display-map CSV  Per-instance display mapping (e.g. 0,1,2)"
      echo "  --master-control   Enable master->follower sync for multi-instance"
      echo "  --no-master-control Disable master->follower sync for multi-instance"
      echo "  --randomize, -z  Randomize grid layouts for each group"
      echo "  --recursive, -R  Recurse into subdirectories"
      echo "  --no-cache       Rebuild randomized tile composites (default: cache enabled)"
      echo "  --animate-videos Render animated tile clips (mp4) instead of still composites"
      echo "  --encoder NAME   Animated tile encoder: auto|hevc_videotoolbox|libx265|libx264"
      echo "  --playlist, -p   Use playlist file for large image sets (ensures all images are loaded)"
      echo "  --random-scale, -rs  Randomly alternate between fill and fit scaling modes"
      exit 0
      ;;
    *)
      # First non-option argument is the directory/glob pattern
      if [[ -z "${DIR:-}" ]]; then
        DIR="$1"
      fi
      shift
      ;;
  esac
done

# Enable shell tracing after arg parsing so debug focuses on runtime logic.
if [ "$DEBUG" = "true" ]; then
  set -x
fi

# Set default directory if not provided
DIR="${DIR:-.}"

if [ -n "$SOUND_FILE" ]; then
  SOUND_FILE="${SOUND_FILE/#\~/$HOME}"
  if [ ! -f "$SOUND_FILE" ]; then
    echo "Sound file not found: $SOUND_FILE"
    exit 1
  fi
fi
if ! [[ "$SOUND_TRIM_DB" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  echo "Invalid --sound-trim-db value: $SOUND_TRIM_DB"
  exit 1
fi
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [ "$LIMIT" -lt 1 ]; then
  echo "Invalid --limit value: $LIMIT (expected positive integer)"
  exit 1
fi
case "$SCALE_MODE" in
  fit|fill)
    ;;
  *)
    echo "Invalid --scale-mode value: $SCALE_MODE (expected: fit or fill)"
    exit 1
    ;;
esac
if ! [[ "$SPACING" =~ ^[0-9]+$ ]]; then
  echo "Invalid --spacing value: $SPACING (expected non-negative integer)"
  exit 1
fi
if ! [[ "$MPV_INSTANCES" =~ ^[0-9]+$ ]] || [ "$MPV_INSTANCES" -lt 1 ]; then
  echo "Invalid --instances value: $MPV_INSTANCES (expected positive integer)"
  exit 1
fi
case "$ANIMATE_VIDEOS" in
  true|false)
    ;;
  *)
    echo "Invalid animate-videos flag value: $ANIMATE_VIDEOS"
    exit 1
    ;;
esac
case "$TILE_VIDEO_ENCODER_OVERRIDE" in
  auto|hevc_videotoolbox|libx265|libx264)
    ;;
  *)
    echo "Invalid --encoder value: $TILE_VIDEO_ENCODER_OVERRIDE"
    echo "Expected: auto, hevc_videotoolbox, libx265, or libx264"
    exit 1
    ;;
esac
case "$MASTER_CONTROL_MODE" in
  yes|no|auto)
    ;;
  *)
    echo "Invalid master control mode: $MASTER_CONTROL_MODE (expected yes|no|auto)"
    exit 1
    ;;
esac
if [ -n "$MAX_FILES" ] && ! [[ "$MAX_FILES" =~ ^[0-9]+$ ]]; then
  echo "Invalid --max-files value: $MAX_FILES"
  exit 1
fi
case "$FILE_ORDER" in
  natural|om)
    ;;
  *)
    echo "Invalid --order value: $FILE_ORDER (expected: natural or om)"
    exit 1
    ;;
esac

cleanup() {
  if [ -n "${BACKGROUND_AUDIO_PID:-}" ]; then
    kill "${BACKGROUND_AUDIO_PID}" 2>/dev/null || true
    wait "${BACKGROUND_AUDIO_PID}" 2>/dev/null || true
  fi
  if [ -n "${TEMP_SOUND_FILE:-}" ] && [ -f "${TEMP_SOUND_FILE}" ]; then
    rm -f "${TEMP_SOUND_FILE}"
  fi
  if [ -n "${RANDOM_SCALE_LUA_SCRIPT:-}" ] && [ -f "${RANDOM_SCALE_LUA_SCRIPT}" ]; then
    rm -f "${RANDOM_SCALE_LUA_SCRIPT}"
  fi
  if [ -n "${TMPLIST:-}" ] && [ -f "${TMPLIST}" ]; then
    rm -f "${TMPLIST}"
  fi
  if [ -n "${TILE_SKIP_LOG:-}" ] && [ -f "${TILE_SKIP_LOG}" ]; then
    rm -f "${TILE_SKIP_LOG}"
  fi
}
trap cleanup EXIT INT TERM

# Extract width and height from resolution
WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2)

sort_discovered_images() {
  local input_file="$1"
  local output_file="$2"

  if [ "$FILE_ORDER" = "natural" ]; then
    sort -V "$input_file" > "$output_file"
    return 0
  fi

  # zsh-like *.png(om): oldest modification time first.
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    mtime=""
    if mtime=$(stat -f '%m' "$img" 2>/dev/null); then
      :
    else
      mtime=$(stat -c '%Y' "$img" 2>/dev/null || echo "0")
    fi
    printf "%s\t%s\n" "$mtime" "$img"
  done < "$input_file" | sort -n -k1,1 | cut -f2- > "$output_file"
}

# Create temporary file list
TMPLIST="$(mktemp)"
TMPLIST_RAW="$(mktemp)"

# Check if DIR contains glob patterns or is a directory
if [[ "$DIR" == *"*"* ]]; then
  # Handle glob patterns - use find instead of ls
  if [ "$RECURSIVE" = "true" ]; then
    find "$(dirname "$DIR")" -name "$(basename "$DIR")" -type f 2>/dev/null > "$TMPLIST_RAW"
  else
    find "$(dirname "$DIR")" -maxdepth 1 -name "$(basename "$DIR")" -type f 2>/dev/null > "$TMPLIST_RAW"
  fi
else
  # Handle directory path - use find for better reliability
  if [ "$RECURSIVE" = "true" ]; then
    find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null > "$TMPLIST_RAW"
  else
    find "$DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null > "$TMPLIST_RAW"
  fi
fi
sort_discovered_images "$TMPLIST_RAW" "$TMPLIST"
rm -f "$TMPLIST_RAW"

if [ -n "$MAX_FILES" ] && [ "$MAX_FILES" -gt 0 ]; then
  sed -n "1,${MAX_FILES}p" "$TMPLIST" > "${TMPLIST}.limited"
  mv "${TMPLIST}.limited" "$TMPLIST"
fi

if [ ! -s "$TMPLIST" ]; then
  echo "No images found in $DIR"
  rm -f "$TMPLIST"
  exit 1
fi

TOTAL=$(wc -l < "$TMPLIST")
echo "Processing $TOTAL images with '$EFFECT' effect..."

get_mpv_pipeline_path() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    local dir
    dir="$(cd "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="${dir}/${source}"
  done
  local repo_root
  repo_root="$(cd "$(dirname "$source")/.." >/dev/null 2>&1 && pwd)"
  echo "${repo_root}/scripts/mpv-pipeline.sh"
}

create_random_scale_script() {
  RANDOM_SCALE_LUA_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/mpv-img-tricks-random-scale.XXXXXX.lua")"
  cat > "$RANDOM_SCALE_LUA_SCRIPT" << 'EOF'
function on_file_loaded()
    if math.random() < 0.5 then
        mp.set_property("video-scale", "crop")
    else
        mp.set_property("video-scale", "fit")
    end
end
EOF
}

run_live_pipeline_effect() {
  local mode="$1"
  local mpv_pipeline
  local loop_mode
  local fullscreen_mode

  mpv_pipeline="$(get_mpv_pipeline_path)"
  if [ ! -x "$mpv_pipeline" ]; then
    echo "Canonical runner not executable: $mpv_pipeline"
    exit 1
  fi

  case "$mode" in
    basic)
      loop_mode="none"
      fullscreen_mode="no"
      ;;
    chaos)
      loop_mode="playlist"
      fullscreen_mode="yes"
      ;;
    *)
      echo "Unknown live mode for pipeline: $mode"
      exit 1
      ;;
  esac

  build_audio_args
  local -a pipeline_args=(
    --playlist "$TMPLIST"
    --duration "$DURATION"
    --fullscreen "$fullscreen_mode"
    --loop-mode "$loop_mode"
    --scale-mode "$SCALE_MODE"
    --instances "$MPV_INSTANCES"
    --master-control "$MASTER_CONTROL_MODE"
    --debug "$DEBUG"
    --mpv-arg "--hr-seek=yes"
    --mpv-arg "--keep-open=no"
  )

  if [ "$mode" = "chaos" ]; then
    pipeline_args+=(--shuffle yes)
  else
    pipeline_args+=(--shuffle no)
    pipeline_args+=(--mpv-arg "--playlist-start=0")
  fi

  if [ -n "$DISPLAY_INDEX" ]; then
    pipeline_args+=(--display "$DISPLAY_INDEX")
  fi
  if [ -n "$DISPLAY_MAP" ]; then
    pipeline_args+=(--display-map "$DISPLAY_MAP")
  fi

  if [ "$RANDOM_SCALE" = "true" ]; then
    create_random_scale_script
    pipeline_args+=(--extra-script "$RANDOM_SCALE_LUA_SCRIPT")
  fi

  if [ -n "$SOUND_FILE" ]; then
    pipeline_args+=(--no-audio no)
    pipeline_args+=(--mpv-arg "--audio-file=$SOUND_FILE")
    pipeline_args+=(--mpv-arg "--audio-display=no")
  else
    pipeline_args+=(--no-audio yes)
  fi

  exec "$mpv_pipeline" "${pipeline_args[@]}"
}

build_tile_cell_filter() {
  local cell_w="$1"
  local cell_h="$2"
  if [ "$SCALE_MODE" = "fill" ]; then
    echo "scale=${cell_w}:${cell_h}:force_original_aspect_ratio=increase,crop=${cell_w}:${cell_h}"
  else
    echo "scale=${cell_w}:${cell_h}:force_original_aspect_ratio=decrease,pad=${cell_w}:${cell_h}:(ow-iw)/2:(oh-ih)/2:black"
  fi
}

# Effect modules
basic_effect() {
  echo "Running basic slideshow..."
  if [ "$USE_PLAYLIST" = "false" ] && [ "$DEBUG" = "true" ]; then
    echo "Debug: canonical runner always consumes discovered playlist (legacy --playlist no longer changes basic/chaos behavior)."
  fi
  run_live_pipeline_effect "basic"
}

chaos_effect() {
  echo "Running chaos slideshow..."
  if [ "$USE_PLAYLIST" = "false" ] && [ "$DEBUG" = "true" ]; then
    echo "Debug: canonical runner always consumes discovered playlist (legacy --playlist no longer changes basic/chaos behavior)."
  fi
  run_live_pipeline_effect "chaos"
}

ken_burns_effect() {
  local out="${OUTPUT:-ken-burns.mp4}"
  local input_list
  echo "Creating Ken Burns effect video..."
  input_list="$(get_limited_video_list "Ken Burns")"

  # Parse resolution
  WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
  HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2)

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    PAN_X=$((RANDOM % 200 - 100))
    PAN_Y=$((RANDOM % 200 - 100))
    FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},zoompan=z='min(zoom+0.0015,1.3)':d=${DURATION}*${FPS}:x='iw/2-(iw/zoom/2)+${PAN_X}':y='ih/2-(ih/zoom/2)+${PAN_Y}':s=${WIDTH}x${HEIGHT}[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Ken Burns video created: $out"
  rm -f "$input_list"
}

glitch_effect() {
  local out="${OUTPUT:-glitch.mp4}"
  local input_list
  echo "Creating glitch effect video..."
  input_list="$(get_limited_video_list "Glitch")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    EFFECT=$((RANDOM % 3))  # Reduced to 3 simpler effects
    case $EFFECT in
      0) FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=90:s=2:b=1.5[v${i}];" ;;
      1) FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},split[g1][g2];[g1]hue=h=0:s=0[g1];[g2]hue=h=180:s=2[g2];[g1][g2]blend=all_mode=difference[v${i}];" ;;
      2) FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=120:s=2:b=0.5[v${i}];" ;;
    esac
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Glitch video created: $out"
  rm -f "$input_list"
}

acid_effect() {
  local out="${OUTPUT:-acid-trip.mp4}"
  local input_list
  echo "Creating acid trip video..."
  input_list="$(get_limited_video_list "Acid")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    TRIP=$((RANDOM % 3))  # Simplified to 3 effects
    case $TRIP in
      0) FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=0:s=3:b=1.5[v${i}];" ;;
      1) FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=120:s=2:b=1.2[v${i}];" ;;
      2) FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=240:s=2.5:b=0.8[v${i}];" ;;
    esac
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Acid trip video created: $out"
  rm -f "$input_list"
}

reality_effect() {
  local out="${OUTPUT:-reality-break.mp4}"
  local input_list
  echo "Breaking reality..."
  input_list="$(get_limited_video_list "Reality")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    EFFECT=$((RANDOM % 4))
    case $EFFECT in
      0) FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2];[r1]vflip[r1];[r2]hflip[r2];[r1][r2]blend=all_mode=difference[v${i}];" ;;
      1) FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2][r3];[r1]hue=h=0[r1];[r2]hue=h=120[r2];[r3]hue=h=240[r3];[r1][r2]blend=all_mode=screen[r12];[r12][r3]blend=all_mode=multiply[v${i}];" ;;
      2) FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2][r3][r4];[r1]hue=h=0[r1];[r2]hue=h=90[r2];[r3]hue=h=180[r3];[r4]hue=h=270[r4];[r1][r2]blend=all_mode=addition[r12];[r3][r4]blend=all_mode=addition[r34];[r12][r34]blend=all_mode=difference[v${i}];" ;;
      3) FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2];[r1]hue=h=0:s=2[r1];[r2]hue=h=180:s=2[r2];[r1][r2]blend=all_mode=difference[v${i}];" ;;
    esac
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 25M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Reality broken: $out"
  rm -f "$input_list"
}

kaleido_effect() {
  local out="${OUTPUT:-kaleido.mp4}"
  local input_list
  echo "Creating INTENSE kaleidoscope patterns..."
  input_list="$(get_limited_video_list "Kaleido")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    # SUPER INTENSE kaleidoscope effect with dramatic hue rotation, high saturation, and brightness
    FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},setsar=1,hue=h=t*180:s=8:b=3.0,eq=contrast=2.0:brightness=0.3:saturation=3.0[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t 0.5 -stream_loop 1 -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 18M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "INTENSE Kaleidoscope video created: $out"
  rm -f "$input_list"
}

matrix_effect() {
  local out="${OUTPUT:-matrix.mp4}"
  local input_list
  echo "Entering the Matrix..."
  input_list="$(get_limited_video_list "Matrix")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},split[m1][m2];[m1]hue=h=120:s=1:b=0.3[m1];[m2]hue=h=0:s=0:b=1[m2];[m1][m2]blend=all_mode=screen[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 16M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Matrix video created: $out"
  rm -f "$input_list"
}

liquid_effect() {
  local out="${OUTPUT:-liquid.mp4}"
  local input_list
  echo "Creating liquid distortion..."
  input_list="$(get_limited_video_list "Liquid")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[l1][l2][l3];[l1]hue=h=45:s=1.5[l1];[l2]hue=h=135:s=1.5[l2];[l3]hue=h=225:s=1.5[l3];[l1][l2]blend=all_mode=addition[l12];[l12][l3]blend=all_mode=addition[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 17M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Liquid video created: $out"
  rm -f "$input_list"
}

tile_effect() {
  echo "Creating live tiled slideshow with mpv..."
  if [ "$ANIMATE_VIDEOS" = "true" ]; then
    configure_tile_video_encoder
  fi
  if [ -n "$SOUND_FILE" ]; then
    start_background_audio_loop
    AUDIO_ARGS=("--no-audio")
  else
    build_audio_args
  fi

  # Detect screen resolution (Linux: xrandr, macOS: system_profiler).
  detect_screen_resolution
  filter_tile_readable_inputs "$TMPLIST" || return 1

  echo "Screen: ${SCREEN_RES}, Duration: ${DURATION}s, Group size: ${GROUP_SIZE}"

  if [ "$RANDOMIZE" = "true" ]; then
    echo "Randomizing grid layouts for each group..."
    tile_effect_randomized
  else
    echo "Using fixed grid: ${GRID}"
    tile_effect_fixed
  fi
}

run_mpv() {
  if [ "$(uname -s)" = "Darwin" ] && [ "$DEBUG" != "true" ]; then
    # Filter known noisy macOS logs while keeping real mpv/ffmpeg errors visible.
    mpv "$@" 2> >(
      awk '
        /CFURLCopyResourcePropertyForKey failed because it was passed a URL which has no scheme/ { next }
        /\+\[IMKClient subclass\]: chose IMKClient_Modern/ { next }
        /\+\[IMKInputSession subclass\]: chose IMKInputSession_Modern/ { next }
        { print }
      ' >&2
    )
  else
    mpv "$@"
  fi
}

build_audio_args() {
  AUDIO_ARGS=()
  if [ -n "$SOUND_FILE" ]; then
    AUDIO_ARGS+=("--audio-file=$SOUND_FILE")
    AUDIO_ARGS+=("--audio-display=no")
  else
    AUDIO_ARGS+=("--no-audio")
  fi
}

build_video_audio_args() {
  local audio_input_index="$1"
  VIDEO_AUDIO_INPUTS=""
  VIDEO_AUDIO_OUTPUT_OPTS="-an"
  if [ -n "$SOUND_FILE" ]; then
    prepare_sound_file
    local audio_path="$PREPARED_SOUND_FILE"
    if [ -z "$audio_path" ] || [ ! -f "$audio_path" ]; then
      echo "Sound file not playable: $SOUND_FILE"
      return 1
    fi
    VIDEO_AUDIO_INPUTS="-stream_loop -1 -i \"$audio_path\""
    VIDEO_AUDIO_OUTPUT_OPTS="-map ${audio_input_index}:a -c:a aac -b:a 192k -shortest"
  fi
}

get_limited_video_list() {
  local effect_name="$1"
  local list_file="${TMPLIST}.video-limit"
  local total_count
  local limited_count

  total_count=$(wc -l < "$TMPLIST")
  sed -n "1,${LIMIT}p" "$TMPLIST" > "$list_file"
  limited_count=$(wc -l < "$list_file")

  if [ "$limited_count" -lt "$total_count" ]; then
    echo "Using first ${limited_count}/${total_count} images for ${effect_name} (--limit memory guard)." >&2
  fi

  echo "$list_file"
}

prepare_sound_file() {
  PREPARED_SOUND_FILE="$SOUND_FILE"
  if [ -z "$SOUND_FILE" ]; then
    return 0
  fi
  if ! command -v ffmpeg >/dev/null 2>&1; then
    return 0
  fi

  TEMP_SOUND_FILE="$(mktemp "${TMPDIR:-/tmp}/mpv-img-tricks-sound.XXXXXX")"
  if ffmpeg -nostdin -loglevel error -y \
    -i "$SOUND_FILE" \
    -af "silenceremove=start_periods=1:start_silence=0:start_threshold=${SOUND_TRIM_DB}dB" \
    -f mp3 \
    "$TEMP_SOUND_FILE"; then
    if [ -s "$TEMP_SOUND_FILE" ]; then
      PREPARED_SOUND_FILE="$TEMP_SOUND_FILE"
      echo "Trimmed leading silence from sound file."
    else
      rm -f "$TEMP_SOUND_FILE"
      TEMP_SOUND_FILE=""
    fi
  else
    rm -f "$TEMP_SOUND_FILE"
    TEMP_SOUND_FILE=""
  fi
}

start_background_audio_loop() {
  if [ -z "$SOUND_FILE" ]; then
    return 0
  fi
  if [ -n "${BACKGROUND_AUDIO_PID:-}" ]; then
    return 0
  fi
  prepare_sound_file
  local audio_path="$PREPARED_SOUND_FILE"
  if [ -z "$audio_path" ] || [ ! -f "$audio_path" ]; then
    echo "Sound file not playable: $SOUND_FILE"
    return 1
  fi
  mpv \
    --no-video \
    --audio-display=no \
    --keep-open=no \
    --loop-file=inf \
    --force-window=no \
    --title=mpv-img-tricks-audio \
    "$audio_path" >/dev/null 2>&1 &
  BACKGROUND_AUDIO_PID="$!"
  echo "Started continuous audio loop."
}

get_rss_kb() {
  local pid="$1"
  local rss
  rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
  if [[ "$rss" =~ ^[0-9]+$ ]]; then
    echo "$rss"
  else
    echo "0"
  fi
}

sum_active_rss_kb() {
  local total=0
  local pid rss
  for pid in "${ACTIVE_PIDS[@]:-}"; do
    rss=$(get_rss_kb "$pid")
    total=$((total + rss))
  done
  echo "$total"
}

detect_screen_resolution() {
  local detected=""
  local os_name
  os_name="$(uname -s)"

  if [ "$os_name" = "Darwin" ]; then
    if command -v system_profiler >/dev/null 2>&1; then
      # Prefer physical panel resolution for collage sizing on macOS.
      detected=$(
        system_profiler SPDisplaysDataType 2>/dev/null \
          | sed -nE 's/.*Resolution:[[:space:]]*([0-9]+)[[:space:]]*x[[:space:]]*([0-9]+).*/\1x\2/p' \
          | head -1
      )
      if [ -z "$detected" ]; then
        detected=$(
          system_profiler SPDisplaysDataType 2>/dev/null \
            | sed -nE 's/.*UI Looks like:[[:space:]]*([0-9]+)[[:space:]]*x[[:space:]]*([0-9]+).*/\1x\2/p' \
            | head -1
        )
      fi
    fi
  else
    if command -v xrandr >/dev/null 2>&1; then
      detected=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')
    fi
  fi

  if [ -z "$detected" ]; then
    detected="$RESOLUTION"
  fi

  SCREEN_RES="$detected"
  SCREEN_WIDTH=$(echo "$SCREEN_RES" | cut -d'x' -f1)
  SCREEN_HEIGHT=$(echo "$SCREEN_RES" | cut -d'x' -f2)
}

filter_tile_readable_inputs() {
  local input_list="$1"
  local checked=0
  local kept=0
  local skipped=0
  local filtered_list

  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe not found; skipping tile media validation."
    return 0
  fi

  filtered_list="$(mktemp)"
  TILE_SKIP_LOG="$(mktemp)"

  while IFS= read -r media; do
    [ -n "$media" ] || continue
    checked=$((checked + 1))
    if ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$media" >/dev/null 2>&1; then
      echo "$media" >> "$filtered_list"
      kept=$((kept + 1))
    else
      echo "$media" >> "$TILE_SKIP_LOG"
      skipped=$((skipped + 1))
    fi
  done < "$input_list"

  mv "$filtered_list" "$input_list"

  if [ "$kept" -eq 0 ]; then
    echo "No readable media remained for tile effect."
    if [ "$skipped" -gt 0 ]; then
      echo "Skipped list saved to: $TILE_SKIP_LOG"
    fi
    return 1
  fi

  if [ "$skipped" -gt 0 ]; then
    echo "Skipped ${skipped}/${checked} unreadable media file(s)."
    echo "Skip log: $TILE_SKIP_LOG"
  else
    rm -f "$TILE_SKIP_LOG"
    TILE_SKIP_LOG=""
  fi
}

is_probably_video_file() {
  local lower_path
  lower_path=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower_path" in
    *.mov|*.mp4|*.m4v|*.mkv|*.webm|*.avi|*.mpg|*.mpeg)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_probably_image_file() {
  local lower_path
  lower_path=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower_path" in
    *.jpg|*.jpeg|*.png|*.webp|*.bmp|*.gif|*.tiff|*.heic)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

configure_tile_video_encoder() {
  local encoder_list
  if [ "$TILE_VIDEO_ENCODER_READY" = "true" ]; then
    return 0
  fi

  TILE_VIDEO_CODEC_ARGS=()
  TILE_VIDEO_ENCODER_NAME=""

  encoder_list="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"

  if [ "$TILE_VIDEO_ENCODER_OVERRIDE" != "auto" ]; then
    if printf '%s' "$encoder_list" | grep -q "$TILE_VIDEO_ENCODER_OVERRIDE"; then
      case "$TILE_VIDEO_ENCODER_OVERRIDE" in
        hevc_videotoolbox)
          TILE_VIDEO_ENCODER_NAME="hevc_videotoolbox"
          TILE_VIDEO_CODEC_ARGS=(-c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p)
          ;;
        libx265)
          TILE_VIDEO_ENCODER_NAME="libx265"
          TILE_VIDEO_CODEC_ARGS=(-c:v libx265 -preset medium -crf 25 -pix_fmt yuv420p)
          ;;
        libx264)
          TILE_VIDEO_ENCODER_NAME="libx264"
          TILE_VIDEO_CODEC_ARGS=(-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p)
          ;;
      esac
      TILE_VIDEO_ENCODER_READY="true"
      echo "Animated tile encoder: ${TILE_VIDEO_ENCODER_NAME} (forced)"
      return 0
    fi
    echo "Requested encoder '$TILE_VIDEO_ENCODER_OVERRIDE' is unavailable; falling back to auto."
  fi

  if printf '%s' "$encoder_list" | grep -q 'hevc_videotoolbox'; then
    TILE_VIDEO_ENCODER_NAME="hevc_videotoolbox"
    TILE_VIDEO_CODEC_ARGS=(-c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p)
  elif printf '%s' "$encoder_list" | grep -q 'libx265'; then
    TILE_VIDEO_ENCODER_NAME="libx265"
    TILE_VIDEO_CODEC_ARGS=(-c:v libx265 -preset medium -crf 25 -pix_fmt yuv420p)
  else
    TILE_VIDEO_ENCODER_NAME="libx264"
    TILE_VIDEO_CODEC_ARGS=(-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p)
  fi

  TILE_VIDEO_ENCODER_READY="true"
  echo "Animated tile encoder: ${TILE_VIDEO_ENCODER_NAME}"
}

tile_effect_fixed() {
  # Parse grid dimensions
  GRID_COLS=$(echo "$GRID" | cut -d'x' -f1)
  GRID_ROWS=$(echo "$GRID" | cut -d'x' -f2)
  TILE_COUNT=$((GRID_COLS * GRID_ROWS))
  INPUT_COUNT=$(wc -l < "$TMPLIST")

  echo "Fixed tile mode"
  echo "Grid: ${GRID_COLS}x${GRID_ROWS}, tiles per frame: ${TILE_COUNT}, input images: ${INPUT_COUNT}"

  # Calculate tile size accounting for requested spacing between cells.
  USABLE_WIDTH=$((SCREEN_WIDTH - SPACING * (GRID_COLS - 1)))
  USABLE_HEIGHT=$((SCREEN_HEIGHT - SPACING * (GRID_ROWS - 1)))
  if [ "$USABLE_WIDTH" -le 0 ] || [ "$USABLE_HEIGHT" -le 0 ]; then
    echo "Spacing (${SPACING}) is too large for grid ${GRID} at screen ${SCREEN_RES}."
    return 1
  fi
  TILE_WIDTH=$((USABLE_WIDTH / GRID_COLS))
  TILE_HEIGHT=$((USABLE_HEIGHT / GRID_ROWS))

  echo "Tile size: ${TILE_WIDTH}x${TILE_HEIGHT} (spacing: ${SPACING}px)"
  echo "Collage output size: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

  # Build generic fixed-grid composite filter (used for slideshow rendering).
  # xstack layout offsets create visible spacing gaps between tiles.
  CELL_FILTER="$(build_tile_cell_filter "$TILE_WIDTH" "$TILE_HEIGHT")"
  FIXED_COMPOSITE_FILTER=""
  for ((i=0; i<TILE_COUNT; i++)); do
    FIXED_COMPOSITE_FILTER="${FIXED_COMPOSITE_FILTER}[${i}:v]${CELL_FILTER}[s${i}];"
  done
  STACK_INPUTS=""
  STACK_LAYOUT=""
  for ((i=0; i<TILE_COUNT; i++)); do
    r=$((i / GRID_COLS))
    c=$((i % GRID_COLS))
    x=$((c * (TILE_WIDTH + SPACING)))
    y=$((r * (TILE_HEIGHT + SPACING)))
    STACK_INPUTS="${STACK_INPUTS}[s${i}]"
    STACK_LAYOUT="${STACK_LAYOUT}${x}_${y}|"
  done
  STACK_LAYOUT="${STACK_LAYOUT%|}"
  if [ "$TILE_COUNT" -eq 1 ]; then
    FIXED_COMPOSITE_FILTER="${FIXED_COMPOSITE_FILTER}[s0]copy[grid];[grid]pad=${SCREEN_WIDTH}:${SCREEN_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[out]"
  else
    FIXED_COMPOSITE_FILTER="${FIXED_COMPOSITE_FILTER}${STACK_INPUTS}xstack=inputs=${TILE_COUNT}:layout=${STACK_LAYOUT}:fill=black[grid];[grid]pad=${SCREEN_WIDTH}:${SCREEN_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[out]"
  fi

  # Spacing requires precomposite rendering path; live lavfi fast path does not
  # support flexible gaps without significantly more complex graph generation.
  if [ "$INPUT_COUNT" -gt "$TILE_COUNT" ] || [ "$SPACING" -gt 0 ]; then
    echo "Fixed grid slideshow mode: building composites across all images..."
    COMPOSITE_DIR="$(mktemp -d)"
    ALL_IMAGES=()
    while IFS= read -r img; do
      ALL_IMAGES+=("$img")
    done < "$TMPLIST"

    total_images="${#ALL_IMAGES[@]}"
    slide=0
    cursor=0
    completed_jobs=0
    ACTIVE_PIDS=()
    render_failures=0

    CPU_COUNT=1
    if command -v sysctl >/dev/null 2>&1; then
      CPU_COUNT=$(sysctl -n hw.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
    elif command -v nproc >/dev/null 2>&1; then
      CPU_COUNT=$(nproc 2>/dev/null || echo 1)
    fi
    if [ -z "$CPU_COUNT" ] || [ "$CPU_COUNT" -lt 1 ]; then
      CPU_COUNT=1
    fi

    if [ "$JOBS" = "auto" ]; then
      PARALLEL_JOBS=$((CPU_COUNT / 2))
      if [ "$PARALLEL_JOBS" -lt 1 ]; then
        PARALLEL_JOBS=1
      fi
    elif [[ "$JOBS" =~ ^[0-9]+$ ]] && [ "$JOBS" -ge 1 ]; then
      PARALLEL_JOBS="$JOBS"
    else
      echo "Invalid --jobs value '$JOBS'; using auto."
      PARALLEL_JOBS=$((CPU_COUNT / 2))
      if [ "$PARALLEL_JOBS" -lt 1 ]; then
        PARALLEL_JOBS=1
      fi
    fi

    MAX_PARALLEL_JOBS=$((CPU_COUNT / 2))
    if [ "$MAX_PARALLEL_JOBS" -lt 1 ]; then
      MAX_PARALLEL_JOBS=1
    fi
    if [ "$PARALLEL_JOBS" -gt "$MAX_PARALLEL_JOBS" ]; then
      PARALLEL_JOBS="$MAX_PARALLEL_JOBS"
    fi

    render_fixed_slide() {
      local out_file="$1"
      local filter="$2"
      shift 2
      if [ "$ANIMATE_VIDEOS" = "true" ]; then
        nice -n 10 ffmpeg -nostdin -loglevel error -threads 1 \
          "$@" \
          -filter_complex "$filter" \
          -map "[out]" \
          -t "$DURATION" \
          -r "$FPS" \
          -an \
          "${TILE_VIDEO_CODEC_ARGS[@]}" \
          "$out_file"
      else
        nice -n 10 ffmpeg -nostdin -loglevel error -threads 1 \
          "$@" \
          -filter_complex "$filter" \
          -map "[out]" \
          -frames:v 1 \
          -q:v 2 \
          "$out_file"
      fi
    }

    echo "Using ${PARALLEL_JOBS} render job(s) on ${CPU_COUNT} CPU core(s)"
    while [ "$cursor" -lt "$total_images" ]; do
      INPUT_ARGS=()
      for ((i=0; i<TILE_COUNT; i++)); do
        idx=$((cursor + i))
        if [ "$idx" -ge "$total_images" ]; then
          idx=$((total_images - 1))
        fi
        if [ "$ANIMATE_VIDEOS" = "true" ]; then
          if is_probably_video_file "${ALL_IMAGES[$idx]}"; then
            INPUT_ARGS+=("-ss" "$TILE_VIDEO_SEEK" "-i" "${ALL_IMAGES[$idx]}")
          else
            INPUT_ARGS+=("-loop" "1" "-t" "$DURATION" "-i" "${ALL_IMAGES[$idx]}")
          fi
        else
          if is_probably_video_file "${ALL_IMAGES[$idx]}"; then
            INPUT_ARGS+=("-ss" "$TILE_VIDEO_SEEK" "-i" "${ALL_IMAGES[$idx]}")
          else
            INPUT_ARGS+=("-i" "${ALL_IMAGES[$idx]}")
          fi
        fi
      done

      if [ "$ANIMATE_VIDEOS" = "true" ]; then
        out_file=$(printf "%s/%04d.mp4" "$COMPOSITE_DIR" "$slide")
      else
        out_file=$(printf "%s/%04d.jpg" "$COMPOSITE_DIR" "$slide")
      fi
      if [ "$PARALLEL_JOBS" -gt 1 ]; then
        render_fixed_slide "$out_file" "$FIXED_COMPOSITE_FILTER" "${INPUT_ARGS[@]}" &
        ACTIVE_PIDS+=("$!")
        while [ "${#ACTIVE_PIDS[@]}" -ge "$PARALLEL_JOBS" ]; do
          if wait "${ACTIVE_PIDS[0]}"; then
            :
          else
            render_failures=$((render_failures + 1))
          fi
          ACTIVE_PIDS=("${ACTIVE_PIDS[@]:1}")
          completed_jobs=$((completed_jobs + 1))
        done
      else
        if render_fixed_slide "$out_file" "$FIXED_COMPOSITE_FILTER" "${INPUT_ARGS[@]}"; then
          :
        else
          render_failures=$((render_failures + 1))
        fi
        completed_jobs=$((completed_jobs + 1))
      fi

      slide=$((slide + 1))
      cursor=$((cursor + TILE_COUNT))
      printf "\rCompositing fixed tiles... queued: %d | done: %d | images: %d/%d   " \
        "$slide" "$completed_jobs" "$cursor" "$total_images"
    done

    for pid in "${ACTIVE_PIDS[@]}"; do
      if wait "$pid"; then
        :
      else
        render_failures=$((render_failures + 1))
      fi
      completed_jobs=$((completed_jobs + 1))
      printf "\rCompositing fixed tiles... queued: %d | done: %d | images: %d/%d   " \
        "$slide" "$completed_jobs" "$cursor" "$total_images"
    done
    printf "\n"

    if [ "$render_failures" -gt 0 ]; then
      echo "Fixed-grid compositing skipped ${render_failures} failed slide(s); continuing with successful renders."
    fi

    COMPOSITE_FILES=()
    local composite_glob='*.jpg'
    if [ "$ANIMATE_VIDEOS" = "true" ]; then
      composite_glob='*.mp4'
    fi
    while IFS= read -r img; do
      COMPOSITE_FILES+=("$img")
    done < <(find "$COMPOSITE_DIR" -maxdepth 1 -type f -name "$composite_glob" 2>/dev/null | sort -V)

    if [ "${#COMPOSITE_FILES[@]}" -eq 0 ]; then
      echo "Failed to create fixed-grid composites."
      rm -rf "$COMPOSITE_DIR"
      return 1
    fi

    echo "Created ${#COMPOSITE_FILES[@]} fixed-grid composites."
    echo "Starting tiled slideshow..."
    if [ "$ANIMATE_VIDEOS" = "true" ]; then
      run_mpv \
        "--geometry=${SCREEN_RES}+0+0" \
        "--fullscreen" \
        "--hr-seek=yes" \
        "--keep-open=no" \
        "${AUDIO_ARGS[@]}" \
        "--loop-playlist=inf" \
        "--media-controls=no" \
        "--input-media-keys=no" \
        "--force-media-title=mpv-img-tricks" \
        "--title=mpv-img-tricks" \
        "${COMPOSITE_FILES[@]}"
    else
      run_mpv \
        "--geometry=${SCREEN_RES}+0+0" \
        "--fullscreen" \
        "--image-display-duration=${DURATION}" \
        "--hr-seek=yes" \
        "--keep-open=no" \
        "${AUDIO_ARGS[@]}" \
        "--loop-playlist=inf" \
        "--media-controls=no" \
        "--input-media-keys=no" \
        "--force-media-title=mpv-img-tricks" \
        "--title=mpv-img-tricks" \
        "${COMPOSITE_FILES[@]}"
    fi

    rm -rf "$COMPOSITE_DIR"
    return 0
  fi

  # Build mpv command with hstack/vstack using arrays (safe for filenames)
  MPV_ARGS=(
    "--geometry=${SCREEN_RES}+0+0"
    "--fullscreen"
    "--image-display-duration=${DURATION}"
    "--hr-seek=yes"
    "--keep-open=no"
    "--loop-playlist=inf"
    "--media-controls=no"
    "--input-media-keys=no"
    "--force-media-title=mpv-img-tricks"
    "--title=mpv-img-tricks"
  )
  MPV_ARGS+=("${AUDIO_ARGS[@]}")

  # Build generic lavfi-complex filter:
  # - scale each source into a tile cell
  # - xstack into grid layout
  # - pad to exact detected screen resolution
  LAVFI_COMPLEX=""
  STACK_INPUTS=""
  STACK_LAYOUT=""
  for ((i=1; i<=TILE_COUNT; i++)); do
    idx0=$((i - 1))
    r=$((idx0 / GRID_COLS))
    c=$((idx0 % GRID_COLS))
    x=$((c * (TILE_WIDTH + SPACING)))
    y=$((r * (TILE_HEIGHT + SPACING)))
    if [ "$SCALE_MODE" = "fill" ]; then
      LAVFI_COMPLEX="${LAVFI_COMPLEX}[vid${i}]scale=${TILE_WIDTH}:${TILE_HEIGHT}:force_original_aspect_ratio=increase,crop=${TILE_WIDTH}:${TILE_HEIGHT}[s${idx0}];"
    else
      LAVFI_COMPLEX="${LAVFI_COMPLEX}[vid${i}]scale=${TILE_WIDTH}:${TILE_HEIGHT}:force_original_aspect_ratio=decrease,pad=${TILE_WIDTH}:${TILE_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[s${idx0}];"
    fi
    STACK_INPUTS="${STACK_INPUTS}[s${idx0}]"
    STACK_LAYOUT="${STACK_LAYOUT}${x}_${y}|"
  done
  STACK_LAYOUT="${STACK_LAYOUT%|}"
  if [ "$TILE_COUNT" -eq 1 ]; then
    LAVFI_COMPLEX="${LAVFI_COMPLEX}[s0]copy[grid];[grid]pad=${SCREEN_WIDTH}:${SCREEN_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[vo]"
  else
    LAVFI_COMPLEX="${LAVFI_COMPLEX}${STACK_INPUTS}xstack=inputs=${TILE_COUNT}:layout=${STACK_LAYOUT}:fill=black[grid];[grid]pad=${SCREEN_WIDTH}:${SCREEN_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[vo]"
  fi

  MPV_ARGS+=("--lavfi-complex=${LAVFI_COMPLEX}")
  echo "lavfi: ${LAVFI_COMPLEX}"

  # Add image files using --external-file
  first_image=true
  attached_files=0
  while IFS= read -r img; do
    if [ "$attached_files" -ge "$TILE_COUNT" ]; then
      break
    fi
    if [ "$first_image" = true ]; then
      MPV_ARGS+=("$img")
      first_image=false
      attached_files=1
    else
      MPV_ARGS+=("--external-file=$img")
      attached_files=$((attached_files + 1))
    fi
  done < "$TMPLIST"

  echo "Starting tiled slideshow..."
  if [ "$first_image" = true ]; then
    echo "No images available for tile effect."
    return 1
  fi
  echo "Attached images to mpv: ${attached_files}"
  if [ "$DEBUG" = "true" ]; then
    echo "mpv args count: ${#MPV_ARGS[@]}"
  fi

  # Execute mpv command
  run_mpv "${MPV_ARGS[@]}"
}

tile_effect_randomized() {
  echo "Creating randomized tiled slideshow..."

  if ! [[ "$GROUP_SIZE" =~ ^[0-9]+$ ]] || [ "$GROUP_SIZE" -lt 1 ]; then
    echo "Invalid group size '${GROUP_SIZE}'. Expected a positive integer."
    return 1
  fi

  # Dynamic rectangular layouts: every cols x rows where cols*rows <= GROUP_SIZE.
  # This removes hardcoded caps and enables more experimental compositions.
  DYNAMIC_LAYOUTS=()
  for ((cols=1; cols<=GROUP_SIZE; cols++)); do
    for ((rows=1; rows<=GROUP_SIZE; rows++)); do
      tiles=$((cols * rows))
      if [ "$tiles" -le "$GROUP_SIZE" ]; then
        DYNAMIC_LAYOUTS+=("${cols}x${rows}:${tiles}")
      fi
    done
  done

  if [ "${#DYNAMIC_LAYOUTS[@]}" -eq 0 ]; then
    echo "No layouts generated for group size ${GROUP_SIZE}."
    return 1
  fi

  echo "Dynamic layout pool: ${#DYNAMIC_LAYOUTS[@]} layouts up to ${GROUP_SIZE} tiles"

  # Load all image paths into an array.
  ALL_IMAGES=()
  while IFS= read -r img; do
    ALL_IMAGES+=("$img")
  done < "$TMPLIST"

  if [ "${#ALL_IMAGES[@]}" -eq 0 ]; then
    echo "No images available for randomized tile effect."
    return 1
  fi

  play_composite_dir() {
    local composite_dir="$1"
    local composite_files=()
    local composite_glob='*.jpg'
    if [ ! -d "$composite_dir" ]; then
      echo "Composite directory not found: $composite_dir"
      return 1
    fi
    if [ "$ANIMATE_VIDEOS" = "true" ]; then
      composite_glob='*.mp4'
    fi
    if ! compgen -G "${composite_dir}/${composite_glob}" > /dev/null; then
      echo "No composite files available to play."
      return 1
    fi
    while IFS= read -r candidate; do
      composite_files+=("$candidate")
    done < <(find "$composite_dir" -maxdepth 1 -type f -name "$composite_glob" 2>/dev/null | sort -V)
    if [ "${#composite_files[@]}" -eq 0 ]; then
      echo "No readable composite files found."
      return 1
    fi

    if [ "$ANIMATE_VIDEOS" = "true" ]; then
      run_mpv \
        "--geometry=${SCREEN_RES}+0+0" \
        "--fullscreen" \
        "--hr-seek=yes" \
        "--keep-open=no" \
        "${AUDIO_ARGS[@]}" \
        "--shuffle" \
        "--loop-playlist=inf" \
        "--background=color" \
        "--border=no" \
        "--media-controls=no" \
        "--input-media-keys=no" \
        "--force-media-title=mpv-img-tricks" \
        "--title=mpv-img-tricks" \
        "${composite_files[@]}"
    else
      run_mpv \
        "--geometry=${SCREEN_RES}+0+0" \
        "--fullscreen" \
        "--image-display-duration=${DURATION}" \
        "--hr-seek=yes" \
        "--keep-open=no" \
        "${AUDIO_ARGS[@]}" \
        "--shuffle" \
        "--loop-playlist=inf" \
        "--background=color" \
        "--border=no" \
        "--media-controls=no" \
        "--input-media-keys=no" \
        "--force-media-title=mpv-img-tricks" \
        "--title=mpv-img-tricks" \
        "${composite_files[@]}"
    fi
  }

  CACHE_ROOT="${HOME}/.cache/mpv-img-tricks/tile-randomized"
  cache_used="false"
  cache_key_tmp="$(mktemp)"
  {
    # Stable cache key: prefer reuse unless user requests --no-cache.
    echo "cache_version=${CACHE_VERSION}"
    echo "effect=tile-randomized"
    echo "source=${DIR}"
    echo "recursive=${RECURSIVE}"
    echo "screen=${SCREEN_RES}"
    echo "group_size=${GROUP_SIZE}"
    echo "layout_mode=dynamic"
    echo "animate_videos=${ANIMATE_VIDEOS}"
    echo "encoder=${TILE_VIDEO_ENCODER_OVERRIDE}"
    echo "duration=${DURATION}"
    echo "fps=${FPS}"
    echo "scale_mode=${SCALE_MODE}"
    echo "spacing=${SPACING}"
  } > "$cache_key_tmp"

  if command -v shasum >/dev/null 2>&1; then
    cache_key="$(shasum -a 256 "$cache_key_tmp" | awk '{print $1}')"
  else
    cache_key="$(cksum "$cache_key_tmp" | awk '{print $1 "-" $2}')"
  fi
  rm -f "$cache_key_tmp"

  if [ "$CACHE_COMPOSITES" = "true" ]; then
    mkdir -p "$CACHE_ROOT"
    COMPOSITE_DIR="${CACHE_ROOT}/${cache_key}"
    PLAYLIST_FILE="${COMPOSITE_DIR}/playlist.m3u"
    if [ -d "$COMPOSITE_DIR" ] && [ -s "$PLAYLIST_FILE" ]; then
      echo "Using cached randomized composites: ${COMPOSITE_DIR}"
      if play_composite_dir "$COMPOSITE_DIR"; then
        return 0
      else
        echo "Cached composites missing/unplayable; rebuilding cache."
      fi
    fi
    rm -rf "$COMPOSITE_DIR"
    mkdir -p "$COMPOSITE_DIR"
    cache_used="true"
  else
    COMPOSITE_DIR="$(mktemp -d)"
    PLAYLIST_FILE="${COMPOSITE_DIR}/playlist.m3u"
  fi

  total_images="${#ALL_IMAGES[@]}"
  cursor=0
  slide=0
  completed_jobs=0
  ACTIVE_PIDS=()
  render_failures=0
  MEM_SAMPLE_INTERVAL=25
  BASE_SELF_RSS_KB=$(get_rss_kb "$$")
  PEAK_SELF_RSS_KB="$BASE_SELF_RSS_KB"
  PEAK_ACTIVE_RSS_KB=0
  LEAK_WARNED="false"
  min_possible_slides=$(((total_images + GROUP_SIZE - 1) / GROUP_SIZE))
  max_possible_slides=$total_images

  CPU_COUNT=1
  if command -v sysctl >/dev/null 2>&1; then
    CPU_COUNT=$(sysctl -n hw.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  elif command -v nproc >/dev/null 2>&1; then
    CPU_COUNT=$(nproc 2>/dev/null || echo 1)
  fi
  if [ -z "$CPU_COUNT" ] || [ "$CPU_COUNT" -lt 1 ]; then
    CPU_COUNT=1
  fi

  if [ "$JOBS" = "auto" ]; then
    # Use half of available CPU cores by default to reduce RAM pressure.
    PARALLEL_JOBS=$((CPU_COUNT / 2))
    if [ "$PARALLEL_JOBS" -lt 1 ]; then
      PARALLEL_JOBS=1
    fi
  elif [[ "$JOBS" =~ ^[0-9]+$ ]] && [ "$JOBS" -ge 1 ]; then
    PARALLEL_JOBS="$JOBS"
  else
    echo "Invalid --jobs value '$JOBS'; using auto."
    PARALLEL_JOBS=$((CPU_COUNT / 2))
    if [ "$PARALLEL_JOBS" -lt 1 ]; then
      PARALLEL_JOBS=1
    fi
  fi

  MAX_PARALLEL_JOBS=$((CPU_COUNT / 2))
  if [ "$MAX_PARALLEL_JOBS" -lt 1 ]; then
    MAX_PARALLEL_JOBS=1
  fi
  if [ "$PARALLEL_JOBS" -gt "$MAX_PARALLEL_JOBS" ]; then
    PARALLEL_JOBS="$MAX_PARALLEL_JOBS"
  fi

  render_randomized_slide() {
    local out_file="$1"
    local filter="$2"
    shift 2
    # Use one ffmpeg thread per job to avoid oversubscribing CPUs.
    if [ "$ANIMATE_VIDEOS" = "true" ]; then
      nice -n 10 ffmpeg -nostdin -loglevel error -threads 1 \
        "$@" \
        -filter_complex "$filter" \
        -map "[out]" \
        -t "$DURATION" \
        -r "$FPS" \
        -an \
        "${TILE_VIDEO_CODEC_ARGS[@]}" \
        "$out_file"
    else
      nice -n 10 ffmpeg -nostdin -loglevel error -threads 1 \
        "$@" \
        -filter_complex "$filter" \
        -map "[out]" \
        -frames:v 1 \
        -q:v 2 \
        "$out_file"
    fi
  }

  echo "Compositing randomized tiled slides..."
  echo "Estimated slide range: ${min_possible_slides}-${max_possible_slides}"
  echo "Using ${PARALLEL_JOBS} render job(s) on ${CPU_COUNT} CPU core(s)"
  while [ "$cursor" -lt "$total_images" ]; do
    remaining=$((total_images - cursor))

    # Pick a random dynamic layout that can be populated by remaining images.
    CANDIDATE_LAYOUTS=()
    for layout_entry in "${DYNAMIC_LAYOUTS[@]}"; do
      layout="${layout_entry%%:*}"
      tiles="${layout_entry##*:}"
      if [ "$tiles" -le "$remaining" ]; then
        CANDIDATE_LAYOUTS+=("$layout")
      fi
    done

    if [ "${#CANDIDATE_LAYOUTS[@]}" -eq 0 ]; then
      break
    fi

    picked_layout="${CANDIDATE_LAYOUTS[$((RANDOM % ${#CANDIDATE_LAYOUTS[@]}))]}"
    layout_cols=$(echo "$picked_layout" | cut -d'x' -f1)
    layout_rows=$(echo "$picked_layout" | cut -d'x' -f2)
    tile_count=$((layout_cols * layout_rows))
    usable_w=$((SCREEN_WIDTH - SPACING * (layout_cols - 1)))
    usable_h=$((SCREEN_HEIGHT - SPACING * (layout_rows - 1)))
    if [ "$usable_w" -le 0 ] || [ "$usable_h" -le 0 ]; then
      echo "Spacing (${SPACING}) too large for layout ${picked_layout}; skipping layout."
      break
    fi
    cell_w=$((usable_w / layout_cols))
    cell_h=$((usable_h / layout_rows))

    INPUT_ARGS=()
    for ((i=0; i<tile_count; i++)); do
      if [ "$ANIMATE_VIDEOS" = "true" ]; then
        if is_probably_video_file "${ALL_IMAGES[$((cursor + i))]}"; then
          INPUT_ARGS+=("-ss" "$TILE_VIDEO_SEEK" "-i" "${ALL_IMAGES[$((cursor + i))]}")
        else
          INPUT_ARGS+=("-loop" "1" "-t" "$DURATION" "-i" "${ALL_IMAGES[$((cursor + i))]}")
        fi
      else
        if is_probably_video_file "${ALL_IMAGES[$((cursor + i))]}"; then
          INPUT_ARGS+=("-ss" "$TILE_VIDEO_SEEK" "-i" "${ALL_IMAGES[$((cursor + i))]}")
        else
          INPUT_ARGS+=("-i" "${ALL_IMAGES[$((cursor + i))]}")
        fi
      fi
    done

    CELL_FILTER="$(build_tile_cell_filter "$cell_w" "$cell_h")"
    FILTER=""
    for ((i=0; i<tile_count; i++)); do
      FILTER="${FILTER}[${i}:v]${CELL_FILTER}[s${i}];"
    done

    STACK_INPUTS=""
    STACK_LAYOUT=""
    for ((i=0; i<tile_count; i++)); do
      r=$((i / layout_cols))
      c=$((i % layout_cols))
      x=$((c * (cell_w + SPACING)))
      y=$((r * (cell_h + SPACING)))
      STACK_INPUTS="${STACK_INPUTS}[s${i}]"
      STACK_LAYOUT="${STACK_LAYOUT}${x}_${y}|"
    done
    STACK_LAYOUT="${STACK_LAYOUT%|}"

    if [ "$ANIMATE_VIDEOS" = "true" ]; then
      out_file=$(printf "%s/%04d.mp4" "$COMPOSITE_DIR" "$slide")
    else
      out_file=$(printf "%s/%04d.jpg" "$COMPOSITE_DIR" "$slide")
    fi
    if [ "$tile_count" -eq 1 ]; then
      FILTER="${FILTER}[s0]copy[grid];[grid]pad=${SCREEN_WIDTH}:${SCREEN_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[out]"
    else
      FILTER="${FILTER}${STACK_INPUTS}xstack=inputs=${tile_count}:layout=${STACK_LAYOUT}:fill=black[grid];[grid]pad=${SCREEN_WIDTH}:${SCREEN_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black[out]"
    fi

    echo "$out_file" >> "$PLAYLIST_FILE"

    if [ "$PARALLEL_JOBS" -gt 1 ]; then
      render_randomized_slide "$out_file" "$FILTER" "${INPUT_ARGS[@]}" &
      ACTIVE_PIDS+=("$!")
      while [ "${#ACTIVE_PIDS[@]}" -ge "$PARALLEL_JOBS" ]; do
        if wait "${ACTIVE_PIDS[0]}"; then
          :
        else
          render_failures=$((render_failures + 1))
        fi
        ACTIVE_PIDS=("${ACTIVE_PIDS[@]:1}")
        completed_jobs=$((completed_jobs + 1))
      done
    else
      if render_randomized_slide "$out_file" "$FILTER" "${INPUT_ARGS[@]}"; then
        :
      else
        render_failures=$((render_failures + 1))
      fi
      completed_jobs=$((completed_jobs + 1))
    fi

    cursor=$((cursor + tile_count))
    slide=$((slide + 1))
    printf "\rCompositing... queued: %d | done: %d | images: %d/%d | layout: %s   " \
      "$slide" "$completed_jobs" "$cursor" "$total_images" "$picked_layout"

    if [ $((slide % MEM_SAMPLE_INTERVAL)) -eq 0 ]; then
      SELF_RSS_KB=$(get_rss_kb "$$")
      ACTIVE_RSS_KB=$(sum_active_rss_kb)
      if [ "$SELF_RSS_KB" -gt "$PEAK_SELF_RSS_KB" ]; then
        PEAK_SELF_RSS_KB="$SELF_RSS_KB"
      fi
      if [ "$ACTIVE_RSS_KB" -gt "$PEAK_ACTIVE_RSS_KB" ]; then
        PEAK_ACTIVE_RSS_KB="$ACTIVE_RSS_KB"
      fi
      if [ "$LEAK_WARNED" != "true" ] && [ "$SELF_RSS_KB" -gt $((BASE_SELF_RSS_KB + 524288)) ]; then
        echo ""
        echo "Warning: script RSS grew >512MB (possible memory pressure)."
        LEAK_WARNED="true"
      fi
      if [ "$DEBUG" = "true" ]; then
        echo ""
        echo "mem: self=$((SELF_RSS_KB / 1024))MB active_ffmpeg=$((ACTIVE_RSS_KB / 1024))MB"
      fi
    fi
  done

  for pid in "${ACTIVE_PIDS[@]}"; do
    if wait "$pid"; then
      :
    else
      render_failures=$((render_failures + 1))
    fi
    completed_jobs=$((completed_jobs + 1))
    printf "\rCompositing... queued: %d | done: %d | images: %d/%d   " \
      "$slide" "$completed_jobs" "$cursor" "$total_images"
  done
  printf "\n"

  FINAL_SELF_RSS_KB=$(get_rss_kb "$$")
  if [ "$FINAL_SELF_RSS_KB" -gt "$PEAK_SELF_RSS_KB" ]; then
    PEAK_SELF_RSS_KB="$FINAL_SELF_RSS_KB"
  fi
  echo "Memory peak: script=${PEAK_SELF_RSS_KB}KB, active_ffmpeg=${PEAK_ACTIVE_RSS_KB}KB"

  if [ "$render_failures" -gt 0 ]; then
    echo "Randomized compositing skipped ${render_failures} failed slide(s); continuing with successful renders."
  fi

  if [ ! -s "$PLAYLIST_FILE" ]; then
    echo "Failed to create randomized tiled slides."
    rm -rf "$COMPOSITE_DIR"
    return 1
  fi

  echo "Created ${slide} randomized tile slides."
  if [ "$cache_used" = "true" ]; then
    echo "Saved cache: ${COMPOSITE_DIR}"
  fi
  echo "Starting randomized tiled slideshow..."
  play_composite_dir "$COMPOSITE_DIR"

  if [ "$cache_used" != "true" ]; then
    rm -rf "$COMPOSITE_DIR"
  fi
}

crossfade_effect() {
  local out="${OUTPUT:-crossfade.mp4}"
  local input_list
  echo "Creating crossfade transitions..."
  input_list="$(get_limited_video_list "Crossfade")"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION}[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$input_list"

  # Create crossfade transitions between images
  TRANSITION_FILTER=""
  for ((j=0; j<i-1; j++)); do
    TRANSITION_FILTER="${TRANSITION_FILTER}[v${j}][v$((j+1))]blend=all_mode=normal:all_opacity=0.5[t${j}];"
  done

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  build_video_audio_args "$i" || return 1
  eval "ffmpeg ${FFMPEG_MEM_ARGS} ${INPUTS} ${VIDEO_AUDIO_INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 12M -pix_fmt yuv420p ${VIDEO_AUDIO_OUTPUT_OPTS} -r ${FPS} -y \"${out}\""
  echo "Crossfade video created: $out"
  rm -f "$input_list"
}

# Main effect dispatcher
case "$EFFECT" in
  basic)
    basic_effect
    ;;
  chaos)
    chaos_effect
    ;;
  ken-burns)
    ken_burns_effect
    ;;
  crossfade)
    crossfade_effect
    ;;
  glitch)
    glitch_effect
    ;;
  acid)
    acid_effect
    ;;
  reality)
    reality_effect
    ;;
  kaleido)
    kaleido_effect
    ;;
  matrix)
    matrix_effect
    ;;
  liquid)
    liquid_effect
    ;;
  tile)
    tile_effect
    ;;
  *)
    echo "Unknown effect: $EFFECT"
    echo "Available effects: basic, chaos, ken-burns, crossfade, glitch, acid, reality, kaleido, matrix, liquid, tile"
    exit 1
    ;;
esac

# Cleanup
rm -f "$TMPLIST"

# Show play command for video outputs
if [[ -n "$OUTPUT" && "$EFFECT" != "basic" && "$EFFECT" != "chaos" ]]; then
  echo "Play with: mpv --fs \"$OUTPUT\""
fi
