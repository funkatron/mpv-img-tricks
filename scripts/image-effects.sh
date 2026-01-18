#!/usr/bin/env bash
set -euo pipefail

# mpv-img-tricks: Unified script with modular effects
# Usage: scripts/image-effects.sh <effect> <images_dir> [options]
#
# Effects:
#   basic     - Simple slideshow
#   chaos     - Shuffled rapid-fire
#   ken-burns - Smooth zoom/pan transitions
#   crossfade - Smooth blending between images
#   glitch    - Datamosh-style corruption effects
#   acid      - Psychedelic color shifting
#   reality   - Physics-breaking impossible effects
#   kaleido   - Kaleidoscope patterns
#   matrix    - Matrix rain effects
#   liquid    - Liquid distortion morphing
#
# Examples:
#   scripts/image-effects.sh basic ~/pics
#   scripts/image-effects.sh chaos ~/pics --duration 0.02
#   scripts/image-effects.sh ken-burns ~/pics --duration 3 --output slideshow.mp4
#   scripts/image-effects.sh acid ~/pics --resolution 1920x1080

# Default values
EFFECT="${1:-basic}"
DURATION="0.05"
OUTPUT=""
RESOLUTION="1920x1080"
FPS="30"
LIMIT="5"  # Default limit for video effects

# Parse command line arguments
shift  # Remove effect from arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --duration|-d)
      DURATION="$2"
      shift 2
      ;;
    --output|-o)
      OUTPUT="$2"
      shift 2
      ;;
    --resolution|-r)
      RESOLUTION="$2"
      shift 2
      ;;
    --fps|-f)
      FPS="$2"
      shift 2
      ;;
    --limit|-l)
      LIMIT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: scripts/image-effects.sh <effect> <images_dir_or_glob> [options]"
      echo "Effects: basic, chaos, ken-burns, crossfade, glitch, acid, reality, kaleido, matrix, liquid"
      echo "Options:"
      echo "  --duration, -d    Duration per image (default: 0.05)"
      echo "  --output, -o      Output file for video effects"
      echo "  --resolution, -r  Output resolution (default: 1920x1080)"
      echo "  --fps, -f        Frames per second (default: 30)"
      echo "  --limit, -l      Max images for video effects (default: 5)"
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

# Set default directory if not provided
DIR="${DIR:-.}"

# Extract width and height from resolution
WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2)

# Create temporary file list
TMPLIST="$(mktemp)"

# Expand tilde if present
DIR="${DIR/#\~/$HOME}"

# Check if DIR contains glob patterns or is a directory
if [[ "$DIR" == *"*"* ]]; then
  # Handle glob patterns - use find instead of ls
  find "$(dirname "$DIR")" -name "$(basename "$DIR")" -type f 2>/dev/null | sort -V > "$TMPLIST"
else
  # Handle directory path - use find for better reliability
  if [[ ! -d "$DIR" ]]; then
    echo "Error: Directory not found: $DIR" >&2
    exit 1
  fi
  find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$TMPLIST"
fi

if [ ! -s "$TMPLIST" ]; then
  echo "Error: No images found in $DIR" >&2
  rm -f "$TMPLIST"
  exit 1
fi

TOTAL=$(wc -l < "$TMPLIST")
echo "Processing $TOTAL images with '$EFFECT' effect..."

# Get script directory for Lua script
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LUA_SCRIPT="${SCRIPT_DIR}/mpv-scripts/blast.lua"

# Helper: Execute ffmpeg with built filter and inputs
# Usage: run_ffmpeg <output> <filter_string> <input_args_array> <bitrate>
run_ffmpeg() {
  local out="$1"
  local filter_str="$2"
  local -n inputs_ref="$3"  # nameref to array
  local bitrate="${4:-15M}"

  # Build concat filter from number of inputs
  local count=${#inputs_ref[@]}
  local concat_inputs=""
  for ((j=0; j<count; j++)); do
    concat_inputs="${concat_inputs}[v${j}]"
  done
  local full_filter="${filter_str}${concat_inputs}concat=n=${count}:v=1:a=0[out]"

  # Run ffmpeg without eval for safety
  if ! ffmpeg "${inputs_ref[@]}" \
    -filter_complex "$full_filter" \
    -map "[out]" \
    -c:v hevc_videotoolbox \
    -tag:v hvc1 \
    -b:v "$bitrate" \
    -pix_fmt yuv420p \
    -an \
    -r "$FPS" \
    -y "$out" 2>/dev/null; then
    echo "Error: Failed to create video" >&2
    return 1
  fi
}

# Effect modules
basic_effect() {
  echo "Running basic slideshow..."
  if [[ "$DIR" == *"*"* ]]; then
    # Handle glob patterns - pass files directly to mpv
    exec mpv \
      --image-display-duration="$DURATION" \
      --hr-seek=yes \
      --keep-open=no \
      --no-audio \
      --playlist-start=0 \
      --loop-file=no \
      --script="$LUA_SCRIPT" \
      $DIR 2>/dev/null
  else
    # Handle directory path
    exec mpv \
      --image-display-duration="$DURATION" \
      --hr-seek=yes \
      --keep-open=no \
      --no-audio \
      --playlist-start=0 \
      --loop-file=no \
      --script="$LUA_SCRIPT" \
      "$DIR"/*.{jpg,JPG,jpeg,JPEG,png,PNG,webp,WEBP} 2>/dev/null
  fi
}

chaos_effect() {
  echo "Running chaos slideshow..."
  if [[ "$DIR" == *"*"* ]]; then
    exec mpv \
      --image-display-duration="$DURATION" \
      --shuffle \
      --loop-playlist=inf \
      --hr-seek=yes \
      --no-audio \
      --fs \
      --script="$LUA_SCRIPT" \
      $DIR 2>/dev/null
  else
    exec mpv \
      --image-display-duration="$DURATION" \
      --shuffle \
      --loop-playlist=inf \
      --hr-seek=yes \
      --no-audio \
      --fs \
      --script="$LUA_SCRIPT" \
      "$DIR"/*.{jpg,JPG,jpeg,JPEG,png,PNG,webp,WEBP} 2>/dev/null
  fi
}

ken_burns_effect() {
  local out="${OUTPUT:-ken-burns.mp4}"
  echo "Creating Ken Burns effect video..."

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    local pan_x=$((RANDOM % 200 - 100))
    local pan_y=$((RANDOM % 200 - 100))
    local zoom_duration=$((DURATION * FPS))

    filter_parts+=("[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},zoompan=z='min(zoom+0.0015,1.3)':d=${zoom_duration}:x='iw/2-(iw/zoom/2)+${pan_x}':y='ih/2-(ih/zoom/2)+${pan_y}':s=${RESOLUTION}[v${i}];")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$TMPLIST"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "15M"; then
    echo "Ken Burns video created: $out"
  fi
}

glitch_effect() {
  local out="${OUTPUT:-glitch.mp4}"
  echo "Creating glitch effect video..."

  # Use limited images for speed
  local limited_list="${TMPLIST}.head"
  head -"$LIMIT" "$TMPLIST" > "$limited_list"

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    local effect_type=$((RANDOM % 3))
    local filter_part=""

    case $effect_type in
      0) filter_part="[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=90:s=2:b=1.5[v${i}];" ;;
      1) filter_part="[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},split[g1][g2];[g1]hue=h=0:s=0[g1];[g2]hue=h=180:s=2[g2];[g1][g2]blend=all_mode=difference[v${i}];" ;;
      2) filter_part="[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=120:s=2:b=0.5[v${i}];" ;;
    esac

    filter_parts+=("$filter_part")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$limited_list"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "15M"; then
    echo "Glitch video created: $out"
  fi
  rm -f "$limited_list"
}

acid_effect() {
  local out="${OUTPUT:-acid-trip.mp4}"
  echo "Creating acid trip video..."

  # Use limited images for speed
  local limited_list="${TMPLIST}.head"
  head -"$LIMIT" "$TMPLIST" > "$limited_list"

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    local trip_type=$((RANDOM % 3))
    local filter_part=""

    case $trip_type in
      0) filter_part="[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=0:s=3:b=1.5[v${i}];" ;;
      1) filter_part="[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=120:s=2:b=1.2[v${i}];" ;;
      2) filter_part="[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hue=h=240:s=2.5:b=0.8[v${i}];" ;;
    esac

    filter_parts+=("$filter_part")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$limited_list"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "15M"; then
    echo "Acid trip video created: $out"
  fi
  rm -f "$limited_list"
}

reality_effect() {
  local out="${OUTPUT:-reality-break.mp4}"
  echo "Breaking reality..."

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    local effect_type=$((RANDOM % 4))
    local filter_part=""

    case $effect_type in
      0) filter_part="[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2];[r1]vflip[r1];[r2]hflip[r2];[r1][r2]blend=all_mode=difference[v${i}];" ;;
      1) filter_part="[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2][r3];[r1]hue=h=0[r1];[r2]hue=h=120[r2];[r3]hue=h=240[r3];[r1][r2]blend=all_mode=screen[r12];[r12][r3]blend=all_mode=multiply[v${i}];" ;;
      2) filter_part="[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2][r3][r4];[r1]hue=h=0[r1];[r2]hue=h=90[r2];[r3]hue=h=180[r3];[r4]hue=h=270[r4];[r1][r2]blend=all_mode=addition[r12];[r3][r4]blend=all_mode=addition[r34];[r12][r34]blend=all_mode=difference[v${i}];" ;;
      3) filter_part="[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[r1][r2];[r1]hue=h=0:s=2[r1];[r2]hue=h=180:s=2[r2];[r1][r2]blend=all_mode=difference[v${i}];" ;;
    esac

    filter_parts+=("$filter_part")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$TMPLIST"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "25M"; then
    echo "Reality broken: $out"
  fi
}

kaleido_effect() {
  local out="${OUTPUT:-kaleido.mp4}"
  echo "Creating INTENSE kaleidoscope patterns..."

  # Use limited images for speed
  local limited_list="${TMPLIST}.head"
  head -"$LIMIT" "$TMPLIST" > "$limited_list"

  local filter_parts=()
  local input_args=()
  local i=0
  local frame_duration="0.5"

  while IFS= read -r img; do
    filter_parts+=("[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},setsar=1,hue=h=t*180:s=8:b=3.0,eq=contrast=2.0:brightness=0.3:saturation=3.0[v${i}];")
    input_args+=(-loop 1 -t "$frame_duration" -stream_loop 1 -i "$img")
    i=$((i+1))
  done < "$limited_list"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "18M"; then
    echo "INTENSE Kaleidoscope video created: $out"
  fi
  rm -f "$limited_list"
}

matrix_effect() {
  local out="${OUTPUT:-matrix.mp4}"
  echo "Entering the Matrix..."

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    filter_parts+=("[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},split[m1][m2];[m1]hue=h=120:s=1:b=0.3[m1];[m2]hue=h=0:s=0:b=1[m2];[m1][m2]blend=all_mode=screen[v${i}];")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$TMPLIST"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "16M"; then
    echo "Matrix video created: $out"
  fi
}

liquid_effect() {
  local out="${OUTPUT:-liquid.mp4}"
  echo "Creating liquid distortion..."

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    filter_parts+=("[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[l1][l2][l3];[l1]hue=h=45:s=1.5[l1];[l2]hue=h=135:s=1.5[l2];[l3]hue=h=225:s=1.5[l3];[l1][l2]blend=all_mode=addition[l12];[l12][l3]blend=all_mode=addition[v${i}];")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$TMPLIST"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "17M"; then
    echo "Liquid video created: $out"
  fi
}

crossfade_effect() {
  local out="${OUTPUT:-crossfade.mp4}"
  echo "Creating crossfade transitions..."

  local filter_parts=()
  local input_args=()
  local i=0

  while IFS= read -r img; do
    filter_parts+=("[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION}[v${i}];")
    input_args+=(-loop 1 -t "$DURATION" -i "$img")
    i=$((i+1))
  done < "$TMPLIST"

  # Combine filter parts
  local full_filter=""
  for part in "${filter_parts[@]}"; do
    full_filter="${full_filter}${part}"
  done

  if run_ffmpeg "$out" "$full_filter" input_args "12M"; then
    echo "Crossfade video created: $out"
  fi
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
  *)
    echo "Unknown effect: $EFFECT"
    echo "Available effects: basic, chaos, ken-burns, crossfade, glitch, acid, reality, kaleido, matrix, liquid"
    exit 1
    ;;
esac

# Cleanup
rm -f "$TMPLIST"

# Show play command for video outputs
if [[ -n "$OUTPUT" && "$EFFECT" != "basic" && "$EFFECT" != "chaos" ]]; then
  echo "Play with: mpv --fs \"$OUTPUT\""
fi
