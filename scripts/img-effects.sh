#!/usr/bin/env bash
set -euo pipefail

# mpv-img-tricks: Unified script with modular effects
# Usage: scripts/img-effects.sh <effect> <images_dir> [options]
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
#   scripts/img-effects.sh basic ~/pics
#   scripts/img-effects.sh chaos ~/pics --duration 0.02
#   scripts/img-effects.sh ken-burns ~/pics --duration 3 --output slideshow.mp4
#   scripts/img-effects.sh acid ~/pics --resolution 1920x1080
#   scripts/img-effects.sh tile ~/pics --grid 2x2 --spacing 10

# Default values
EFFECT="${1:-basic}"
DURATION="0.05"
OUTPUT=""
RESOLUTION="1920x1080"
FPS="30"
LIMIT="5"  # Default limit for video effects
GRID="2x2"  # Default grid size for tile effect
SPACING="10"  # Default spacing between tiles
FRAMES_PER_GRID="1"  # How many frames to show each grid before advancing
GROUP_SIZE="4"  # Number of images per group for randomization
RANDOMIZE="false"  # Whether to randomize grid layouts
RECURSIVE="false"  # Whether to recurse into subdirectories
USE_PLAYLIST="false"  # Whether to use playlist file for large image sets
RANDOM_SCALE="false"  # Whether to randomly alternate between fill and fit scaling
CACHE_COMPOSITES="true"  # Cache randomized tile composites by default
CACHE_VERSION="v2"  # Bump when randomized composite behavior changes
JOBS="auto"  # Parallel jobs for randomized tile compositing

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
    --frames-per-grid|-fpg)
      if [[ "$1" == *"="* ]]; then
        FRAMES_PER_GRID="${1#*=}"
        shift
      else
        FRAMES_PER_GRID="$2"
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
    --randomize|-z)
      RANDOMIZE="true"
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
      echo "  --limit, -l      Max images for video effects (default: 5)"
      echo "  --grid, -g       Grid size for tile effect (default: 2x2)"
      echo "  --spacing, -s    Spacing between tiles in pixels (default: 10)"
      echo "  --frames-per-grid, -fpg  Frames per grid before advancing (default: 1)"
      echo "  --group-size, -gs  Number of images per group for randomization (default: 4)"
      echo "  --jobs, -j N       Parallel render jobs for randomized tile (default: auto)"
      echo "  --randomize, -z  Randomize grid layouts for each group"
      echo "  --recursive, -R  Recurse into subdirectories"
      echo "  --no-cache       Rebuild randomized tile composites (default: cache enabled)"
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

# Set default directory if not provided
DIR="${DIR:-.}"

# Extract width and height from resolution
WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2)

# Create temporary file list
TMPLIST="$(mktemp)"

# Check if DIR contains glob patterns or is a directory
if [[ "$DIR" == *"*"* ]]; then
  # Handle glob patterns - use find instead of ls
  if [ "$RECURSIVE" = "true" ]; then
    find "$(dirname "$DIR")" -name "$(basename "$DIR")" -type f 2>/dev/null | sort -V > "$TMPLIST"
  else
    find "$(dirname "$DIR")" -maxdepth 1 -name "$(basename "$DIR")" -type f 2>/dev/null | sort -V > "$TMPLIST"
  fi
else
  # Handle directory path - use find for better reliability
  if [ "$RECURSIVE" = "true" ]; then
    find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$TMPLIST"
  else
    find "$DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$TMPLIST"
  fi
fi

if [ ! -s "$TMPLIST" ]; then
  echo "No images found in $DIR"
  rm -f "$TMPLIST"
  exit 1
fi

TOTAL=$(wc -l < "$TMPLIST")
echo "Processing $TOTAL images with '$EFFECT' effect..."

# Function to get random scaling mode
get_random_scale() {
  if [ "$RANDOM_SCALE" = "true" ]; then
    # Randomly choose between fill (crop to fill screen) and fit (fit within screen)
    if [ $((RANDOM % 2)) -eq 0 ]; then
      echo "crop"  # Fill screen (crop excess)
    else
      echo "fit"   # Fit within screen (letterbox/pillarbox)
    fi
  else
    echo "fit"     # Default behavior
  fi
}

# Effect modules
basic_effect() {
  echo "Running basic slideshow..."

  if [ "$USE_PLAYLIST" = "true" ]; then
    # Use playlist file for large image sets
    PLAYLIST_FILE="$(mktemp)"
    echo "Creating playlist with $TOTAL images..."

    # Create playlist file with all images
    while IFS= read -r img; do
      echo "$img" >> "$PLAYLIST_FILE"
    done < "$TMPLIST"

    echo "Starting basic slideshow with playlist..."
    if [ "$RANDOM_SCALE" = "true" ]; then
      echo "Using random fill/fit scaling..."
      # Create a Lua script for random scaling
      LUA_SCRIPT="$(mktemp).lua"
      cat > "$LUA_SCRIPT" << 'EOF'
function on_file_loaded()
    -- Randomly choose between fill (crop) and fit scaling
    if math.random() < 0.5 then
        mp.set_property("video-scale", "crop")  -- Fill screen
    else
        mp.set_property("video-scale", "fit")    -- Fit within screen
    end
end
EOF
      exec mpv \
        --image-display-duration="$DURATION" \
        --hr-seek=yes \
        --keep-open=no \
        --no-audio \
        --playlist-start=0 \
        --loop-file=no \
        --script="$LUA_SCRIPT" \
        --playlist="$PLAYLIST_FILE" 2>/dev/null
    else
      exec mpv \
        --image-display-duration="$DURATION" \
        --hr-seek=yes \
        --keep-open=no \
        --no-audio \
        --playlist-start=0 \
        --loop-file=no \
        --playlist="$PLAYLIST_FILE" 2>/dev/null
    fi
  else
    # Original behavior for smaller sets
    if [[ "$DIR" == *"*"* ]]; then
      # Handle glob patterns - pass files directly to mpv
      exec mpv \
        --image-display-duration="$DURATION" \
        --hr-seek=yes \
        --keep-open=no \
        --no-audio \
        --playlist-start=0 \
        --loop-file=no \
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
        "$DIR"/*.{jpg,JPG,jpeg,JPEG,png,PNG,webp,WEBP} 2>/dev/null
    fi
  fi
}

chaos_effect() {
  echo "Running chaos slideshow..."

  if [ "$USE_PLAYLIST" = "true" ]; then
    # Use playlist file for large image sets
    PLAYLIST_FILE="$(mktemp)"
    echo "Creating playlist with $TOTAL images..."

    # Create playlist file with all images
    while IFS= read -r img; do
      echo "$img" >> "$PLAYLIST_FILE"
    done < "$TMPLIST"

    echo "Starting chaos slideshow with playlist..."
    if [ "$RANDOM_SCALE" = "true" ]; then
      echo "Using random fill/fit scaling..."
      # Create a Lua script for random scaling
      LUA_SCRIPT="$(mktemp).lua"
      cat > "$LUA_SCRIPT" << 'EOF'
function on_file_loaded()
    -- Randomly choose between fill (crop) and fit scaling
    if math.random() < 0.5 then
        mp.set_property("video-scale", "crop")  -- Fill screen
    else
        mp.set_property("video-scale", "fit")    -- Fit within screen
    end
end
EOF
      exec mpv \
        --image-display-duration="$DURATION" \
        --shuffle \
        --loop-playlist=inf \
        --hr-seek=yes \
        --no-audio \
        --fs \
        --script="$LUA_SCRIPT" \
        --playlist="$PLAYLIST_FILE" 2>/dev/null
    else
      exec mpv \
        --image-display-duration="$DURATION" \
        --shuffle \
        --loop-playlist=inf \
        --hr-seek=yes \
        --no-audio \
        --fs \
        --playlist="$PLAYLIST_FILE" 2>/dev/null
    fi
  else
    # Original behavior for smaller sets
    if [[ "$DIR" == *"*"* ]]; then
      exec mpv \
        --image-display-duration="$DURATION" \
        --shuffle \
        --loop-playlist=inf \
        --hr-seek=yes \
        --no-audio \
        --fs \
        $DIR 2>/dev/null
    else
      exec mpv \
        --image-display-duration="$DURATION" \
        --shuffle \
        --loop-playlist=inf \
        --hr-seek=yes \
        --no-audio \
        --fs \
        "$DIR"/*.{jpg,JPG,jpeg,JPEG,png,PNG,webp,WEBP} 2>/dev/null
    fi
  fi
}

ken_burns_effect() {
  local out="${OUTPUT:-ken-burns.mp4}"
  echo "Creating Ken Burns effect video..."

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
  done < "$TMPLIST"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Ken Burns video created: $out"
}

glitch_effect() {
  local out="${OUTPUT:-glitch.mp4}"
  echo "Creating glitch effect video..."

  # Take only first LIMIT images for speed
  head -"$LIMIT" "$TMPLIST" > "${TMPLIST}.head"

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
  done < "${TMPLIST}.head"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Glitch video created: $out"
  rm -f "${TMPLIST}.head"
}

acid_effect() {
  local out="${OUTPUT:-acid-trip.mp4}"
  echo "Creating acid trip video..."

  # Take only first LIMIT images for speed
  head -"$LIMIT" "$TMPLIST" > "${TMPLIST}.head"

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
  done < "${TMPLIST}.head"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 15M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Acid trip video created: $out"
  rm -f "${TMPLIST}.head"
}

reality_effect() {
  local out="${OUTPUT:-reality-break.mp4}"
  echo "Breaking reality..."

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
  done < "$TMPLIST"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 25M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Reality broken: $out"
}

kaleido_effect() {
  local out="${OUTPUT:-kaleido.mp4}"
  echo "Creating INTENSE kaleidoscope patterns..."

  # Take only first LIMIT images for speed
  head -"$LIMIT" "$TMPLIST" > "${TMPLIST}.head"

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    # SUPER INTENSE kaleidoscope effect with dramatic hue rotation, high saturation, and brightness
    FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},setsar=1,hue=h=t*180:s=8:b=3.0,eq=contrast=2.0:brightness=0.3:saturation=3.0[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t 0.5 -stream_loop 1 -i \"${img}\" "
    i=$((i+1))
  done < "${TMPLIST}.head"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 18M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "INTENSE Kaleidoscope video created: $out"
  rm -f "${TMPLIST}.head"
}

matrix_effect() {
  local out="${OUTPUT:-matrix.mp4}"
  echo "Entering the Matrix..."

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    FILTER="${FILTER}[${i}:v]scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},split[m1][m2];[m1]hue=h=120:s=1:b=0.3[m1];[m2]hue=h=0:s=0:b=1[m2];[m1][m2]blend=all_mode=screen[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$TMPLIST"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 16M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Matrix video created: $out"
}

liquid_effect() {
  local out="${OUTPUT:-liquid.mp4}"
  echo "Creating liquid distortion..."

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION},split[l1][l2][l3];[l1]hue=h=45:s=1.5[l1];[l2]hue=h=135:s=1.5[l2];[l3]hue=h=225:s=1.5[l3];[l1][l2]blend=all_mode=addition[l12];[l12][l3]blend=all_mode=addition[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$TMPLIST"

  CONCAT_FILTER=""
  for ((j=0; j<i; j++)); do
    CONCAT_FILTER="${CONCAT_FILTER}[v${j}]"
  done
  CONCAT_FILTER="${CONCAT_FILTER}concat=n=${i}:v=1:a=0[out]"

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 17M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Liquid video created: $out"
}

tile_effect() {
  echo "Creating live tiled slideshow with mpv..."

  # Detect screen resolution (Linux: xrandr, macOS: system_profiler).
  detect_screen_resolution

  echo "Screen: ${SCREEN_RES}, Duration: ${DURATION}s, Group size: ${GROUP_SIZE}"

  if [ "$RANDOMIZE" = "true" ]; then
    echo "Randomizing grid layouts for each group..."
    tile_effect_randomized
  else
    echo "Using fixed grid: ${GRID}"
    tile_effect_fixed
  fi
}

detect_screen_resolution() {
  local detected=""

  if command -v xrandr >/dev/null 2>&1; then
    detected=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')
  fi

  if [ -z "$detected" ] && command -v system_profiler >/dev/null 2>&1; then
    detected=$(
      system_profiler SPDisplaysDataType 2>/dev/null \
        | sed -nE 's/.*UI Looks like:[[:space:]]*([0-9]+)[[:space:]]*x[[:space:]]*([0-9]+).*/\1x\2/p' \
        | head -1
    )
    if [ -z "$detected" ]; then
      detected=$(
        system_profiler SPDisplaysDataType 2>/dev/null \
          | sed -nE 's/.*Resolution:[[:space:]]*([0-9]+)[[:space:]]*x[[:space:]]*([0-9]+).*/\1x\2/p' \
          | head -1
      )
    fi
  fi

  if [ -z "$detected" ]; then
    detected="$RESOLUTION"
  fi

  SCREEN_RES="$detected"
  SCREEN_WIDTH=$(echo "$SCREEN_RES" | cut -d'x' -f1)
  SCREEN_HEIGHT=$(echo "$SCREEN_RES" | cut -d'x' -f2)
}

tile_effect_fixed() {
  # Parse grid dimensions
  GRID_COLS=$(echo "$GRID" | cut -d'x' -f1)
  GRID_ROWS=$(echo "$GRID" | cut -d'x' -f2)
  TILE_COUNT=$((GRID_COLS * GRID_ROWS))

  echo "Grid: ${GRID_COLS}x${GRID_ROWS}, Tile count: ${TILE_COUNT}"

  # Calculate optimal tile size for screen
  TILE_WIDTH=$((SCREEN_WIDTH / GRID_COLS))
  TILE_HEIGHT=$((SCREEN_HEIGHT / GRID_ROWS))

  echo "Tile size: ${TILE_WIDTH}x${TILE_HEIGHT}"

  # Build mpv command with hstack/vstack using arrays (safe for filenames)
  MPV_ARGS=(
    "--geometry=${SCREEN_RES}+0+0"
    "--image-display-duration=${DURATION}"
    "--hr-seek=yes"
    "--keep-open=no"
    "--no-audio"
    "--loop-playlist=inf"
  )

  # Build lavfi-complex filter for tiling
  LAVFI_COMPLEX=""

  if [ $GRID_ROWS -eq 1 ]; then
    # Single row - use hstack
    if [ $TILE_COUNT -eq 1 ]; then
      LAVFI_COMPLEX="[vid1]copy[vo]"
    elif [ $TILE_COUNT -eq 2 ]; then
      LAVFI_COMPLEX="[vid1][vid2]hstack[vo]"
    elif [ $TILE_COUNT -eq 3 ]; then
      LAVFI_COMPLEX="[vid1][vid2][vid3]hstack=3[vo]"
    elif [ $TILE_COUNT -eq 4 ]; then
      LAVFI_COMPLEX="[vid1][vid2][vid3][vid4]hstack=4[vo]"
    fi
  else
    # Multiple rows - use hstack + vstack
    if [ $GRID_ROWS -eq 2 ] && [ $GRID_COLS -eq 2 ]; then
      # 2x2 grid
      LAVFI_COMPLEX="[vid1][vid2]hstack[row0];[vid3][vid4]hstack[row1];[row0][row1]vstack[vo]"
    elif [ $GRID_ROWS -eq 2 ] && [ $GRID_COLS -eq 3 ]; then
      # 3x2 grid
      LAVFI_COMPLEX="[vid1][vid2][vid3]hstack=3[row0];[vid4][vid5][vid6]hstack=3[row1];[row0][row1]vstack[vo]"
    elif [ $GRID_ROWS -eq 3 ] && [ $GRID_COLS -eq 2 ]; then
      # 2x3 grid
      LAVFI_COMPLEX="[vid1][vid2]hstack[row0];[vid3][vid4]hstack[row1];[vid5][vid6]hstack[row2];[row0][row1][row2]vstack=3[vo]"
    fi
  fi

  MPV_ARGS+=("--lavfi-complex=${LAVFI_COMPLEX}")

  # Add image files using --external-file
  first_image=true
  while IFS= read -r img; do
    if [ "$first_image" = true ]; then
      MPV_ARGS+=("$img")
      first_image=false
    else
      MPV_ARGS+=("--external-file=$img")
    fi
  done < "$TMPLIST"

  echo "Starting tiled slideshow..."
  if [ "$first_image" = true ]; then
    echo "No images available for tile effect."
    return 1
  fi

  # Execute mpv command
  mpv "${MPV_ARGS[@]}"
}

tile_effect_randomized() {
  echo "Creating randomized tiled slideshow..."

  # Define possible grid layouts for randomization (filtered by group size)
  GRID_LAYOUTS=(
    "1x1" "1x2" "2x1" "1x3" "3x1" "2x2" "1x4" "4x1" "2x3" "3x2"
  )

  # Filter layouts to only include those that can fit the group size
  VALID_LAYOUTS=()
  for layout in "${GRID_LAYOUTS[@]}"; do
    cols=$(echo "$layout" | cut -d'x' -f1)
    rows=$(echo "$layout" | cut -d'x' -f2)
    tile_count=$((cols * rows))
    if [ $tile_count -le $GROUP_SIZE ]; then
      VALID_LAYOUTS+=("$layout")
    fi
  done

  if [ "${#VALID_LAYOUTS[@]}" -eq 0 ]; then
    echo "No valid layouts available for group size ${GROUP_SIZE}."
    return 1
  fi

  echo "Valid layouts for group size ${GROUP_SIZE}: ${VALID_LAYOUTS[*]}"

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
    local first_file=""
    if [ ! -d "$composite_dir" ]; then
      echo "Composite directory not found: $composite_dir"
      return 1
    fi
    if ! compgen -G "${composite_dir}/*.jpg" > /dev/null; then
      echo "No composite files available to play."
      return 1
    fi
    first_file=$(find "$composite_dir" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null | sort -V | head -1)
    if [ -z "$first_file" ]; then
      echo "No readable composite files found."
      return 1
    fi

    mpv \
      "--geometry=${SCREEN_RES}+0+0" \
      "--image-display-duration=${DURATION}" \
      "--hr-seek=yes" \
      "--keep-open=no" \
      "--no-audio" \
      "--autocreate-playlist=filter" \
      "--loop-playlist=inf" \
      "--background=color" \
      "--border=no" \
      "--media-controls=no" \
      "--input-media-keys=no" \
      "--force-media-title=mpv-img-tricks" \
      "--title=mpv-img-tricks" \
      "$first_file"
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
    echo "layouts=${VALID_LAYOUTS[*]}"
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
    # Leave one core free by default to keep the desktop responsive.
    PARALLEL_JOBS=$((CPU_COUNT - 1))
    if [ "$PARALLEL_JOBS" -lt 1 ]; then
      PARALLEL_JOBS=1
    fi
  elif [[ "$JOBS" =~ ^[0-9]+$ ]] && [ "$JOBS" -ge 1 ]; then
    PARALLEL_JOBS="$JOBS"
  else
    echo "Invalid --jobs value '$JOBS'; using auto."
    PARALLEL_JOBS=$((CPU_COUNT - 1))
    if [ "$PARALLEL_JOBS" -lt 1 ]; then
      PARALLEL_JOBS=1
    fi
  fi

  if [ "$PARALLEL_JOBS" -gt "$CPU_COUNT" ]; then
    PARALLEL_JOBS="$CPU_COUNT"
  fi

  render_randomized_slide() {
    local out_file="$1"
    local filter="$2"
    shift 2
    # Use one ffmpeg thread per job to avoid oversubscribing CPUs.
    nice -n 10 ffmpeg -nostdin -loglevel error -threads 1 \
      "$@" \
      -filter_complex "$filter" \
      -map "[out]" \
      -frames:v 1 \
      -q:v 2 \
      "$out_file"
  }

  echo "Compositing randomized tiled slides..."
  echo "Estimated slide range: ${min_possible_slides}-${max_possible_slides}"
  echo "Using ${PARALLEL_JOBS} render job(s) on ${CPU_COUNT} CPU core(s)"
  while [ "$cursor" -lt "$total_images" ]; do
    remaining=$((total_images - cursor))

    # Pick a random layout that can be fully populated by remaining images.
    CANDIDATE_LAYOUTS=()
    for layout in "${VALID_LAYOUTS[@]}"; do
      cols=$(echo "$layout" | cut -d'x' -f1)
      rows=$(echo "$layout" | cut -d'x' -f2)
      tiles=$((cols * rows))
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
    cell_w=$((SCREEN_WIDTH / layout_cols))
    cell_h=$((SCREEN_HEIGHT / layout_rows))

    INPUT_ARGS=()
    for ((i=0; i<tile_count; i++)); do
      INPUT_ARGS+=("-i" "${ALL_IMAGES[$((cursor + i))]}")
    done

    FILTER=""
    for ((i=0; i<tile_count; i++)); do
      FILTER="${FILTER}[${i}:v]scale=${cell_w}:${cell_h}:force_original_aspect_ratio=increase,crop=${cell_w}:${cell_h}[s${i}];"
    done

    for ((r=0; r<layout_rows; r++)); do
      row_labels=""
      for ((c=0; c<layout_cols; c++)); do
        idx=$((r * layout_cols + c))
        row_labels="${row_labels}[s${idx}]"
      done

      if [ "$layout_cols" -eq 1 ]; then
        FILTER="${FILTER}${row_labels}copy[row${r}];"
      else
        FILTER="${FILTER}${row_labels}hstack=inputs=${layout_cols}[row${r}];"
      fi
    done

    out_file=$(printf "%s/%04d.jpg" "$COMPOSITE_DIR" "$slide")
    if [ "$layout_rows" -eq 1 ]; then
      FILTER="${FILTER}[row0]copy[out]"
    else
      stacked_rows=""
      for ((r=0; r<layout_rows; r++)); do
        stacked_rows="${stacked_rows}[row${r}]"
      done
      FILTER="${FILTER}${stacked_rows}vstack=inputs=${layout_rows}[out]"
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

  if [ "$render_failures" -gt 0 ]; then
    echo "Compositing failed for ${render_failures} slide(s)."
    rm -rf "$COMPOSITE_DIR"
    return 1
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
  echo "Creating crossfade transitions..."

  FILTER=""
  INPUTS=""
  i=0

  while IFS= read -r img; do
    FILTER="${FILTER}[${i}:v]scale=${RESOLUTION}:force_original_aspect_ratio=increase,crop=${RESOLUTION}[v${i}];"
    INPUTS="${INPUTS}-loop 1 -t ${DURATION} -i \"${img}\" "
    i=$((i+1))
  done < "$TMPLIST"

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

  eval "ffmpeg ${INPUTS} -filter_complex \"${FILTER}${CONCAT_FILTER}\" -map \"[out]\" -c:v hevc_videotoolbox -tag:v hvc1 -b:v 12M -pix_fmt yuv420p -an -r ${FPS} -y \"${out}\""
  echo "Crossfade video created: $out"
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
