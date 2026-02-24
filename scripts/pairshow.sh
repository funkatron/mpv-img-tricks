#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

usage() {
  cat >&2 <<'EOF'
Usage: pairshow.sh <h|v> <duration> [count] [fit|fill] [multi] [random] [files...]
  h|v      : horizontal or vertical stacking
  duration : seconds per slide
  count    : images per composite (default: auto, based on screen size)
  fit|fill : fit preserves aspect ratio (default), fill crops to uniform cells
  multi    : launch one instance per connected display
  random   : shuffle images before splitting across displays
  files    : image files (if omitted, uses *.jpg in cwd)
EOF
  exit 1
}

MODE="${1:-h}"
DUR="${2:-4}"
shift 2 || usage

# Optional positional args: [count] [fit|fill]
COUNT="auto"
SCALE="fit"
if [[ ${1:-} =~ ^[0-9]+$ ]]; then
  COUNT="$1"
  shift
fi
if [[ ${1:-} == "fit" || ${1:-} == "fill" ]]; then
  SCALE="$1"
  shift
fi
MULTI=false
RANDOM_ORDER=false
while [[ ${1:-} == "multi" || ${1:-} == "random" ]]; do
  [[ "$1" == "multi" ]] && MULTI=true
  [[ "$1" == "random" ]] && RANDOM_ORDER=true
  shift
done

files=( "$@" )
if (( ${#files[@]} == 0 )); then
  files=( *.jpg )
fi
n=${#files[@]}
if (( n < 2 )); then
  echo "Need at least 2 images (got $n)." >&2
  exit 1
fi

# --- Multi-display dispatch ---
if [[ "$MULTI" == true ]]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  num_displays=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Resolution:')
  if (( num_displays < 2 )); then
    echo "Only $num_displays display detected, running single instance." >&2
    MULTI=false
  else
    echo "Launching on $num_displays displays ($n images total)..." >&2

    if [[ "$RANDOM_ORDER" == true ]]; then
      oldIFS="$IFS"; IFS=$'\n'
      files=( $(printf '%s\n' "${files[@]}" | perl -MList::Util=shuffle -e 'print shuffle(<>)') )
      IFS="$oldIFS"
      n=${#files[@]}
    fi

    # Build args to forward (count, scale — but not multi/random)
    fwd_args=("$MODE" "$DUR")
    [[ "$COUNT" != "auto" ]] && fwd_args+=("$COUNT")
    [[ "$SCALE" != "fit" ]] && fwd_args+=("$SCALE")

    child_pids=()
    for ((d=0; d<num_displays; d++)); do
      # Collect this display's subset via round-robin
      subset=()
      for ((i=d; i<n; i+=num_displays)); do
        subset+=( "${files[i]}" )
      done
      if (( ${#subset[@]} < 2 )); then
        echo "  Screen $d: skipped (only ${#subset[@]} images)" >&2
        continue
      fi
      echo "  Screen $d: ${#subset[@]} images" >&2
      PAIRSHOW_FS_SCREEN="$d" "$SELF" "${fwd_args[@]}" "${subset[@]}" &
      child_pids+=($!)
    done

    # Wait for all children; propagate first failure
    rc=0
    for pid in "${child_pids[@]}"; do
      wait "$pid" || rc=$?
    done
    exit "$rc"
  fi
fi

# --- Screen detection ---
get_screen_size() {
  local prof
  prof="$(system_profiler SPDisplaysDataType 2>/dev/null)"
  local w h
  if read -r w h < <(echo "$prof" | sed -n 's/.*UI Looks like: *\([0-9]*\) *x *\([0-9]*\).*/\1 \2/p' | head -1); then
    if [[ -n "$w" && -n "$h" ]]; then
      echo "$w $h"
      return
    fi
  fi
  read -r w h < <(echo "$prof" | sed -n 's/.*Resolution: *\([0-9]*\) *x *\([0-9]*\).*/\1 \2/p' | head -1)
  echo "${w:-1920} ${h:-1080}"
}

# --- Detect screen size (needed for auto-count and fill mode) ---
screen_w="" screen_h=""
if [[ "$COUNT" == "auto" || "$SCALE" == "fill" ]]; then
  read -r screen_w screen_h < <(get_screen_size)
  echo "Screen ${screen_w}x${screen_h}" >&2
fi

if [[ "$COUNT" == "auto" ]]; then
  if [[ "$MODE" == "v" ]]; then
    MIN_VISIBLE=360
    COUNT=$(( screen_h / MIN_VISIBLE ))
  else
    MIN_VISIBLE=480
    COUNT=$(( screen_w / MIN_VISIBLE ))
  fi
  # Clamp to [2, 6]
  (( COUNT < 2 )) && COUNT=2
  (( COUNT > 6 )) && COUNT=6
  echo "Auto count: $COUNT per slide" >&2
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- Build ffmpeg filter for a group of $grp_n images ---
# Args: grp_n mode ref_h ref_w scale [cell_w cell_h]
build_filter() {
  local grp_n="$1" mode="$2" ref_h="$3" ref_w="$4" scale="$5"
  local cell_w="${6:-}" cell_h="${7:-}"
  local filter="" labels=""

  if (( grp_n == 1 )); then
    if [[ "$scale" == "fill" && -n "$cell_w" && -n "$cell_h" ]]; then
      echo "[0:v]scale=${cell_w}:${cell_h}:force_original_aspect_ratio=increase,crop=${cell_w}:${cell_h}"
    else
      echo "[0:v]null"
    fi
    return
  fi

  if [[ "$scale" == "fill" && -n "$cell_w" && -n "$cell_h" ]]; then
    # Fill: scale+crop ALL inputs to uniform screen-based cell size
    local scale_crop="scale=${cell_w}:${cell_h}:force_original_aspect_ratio=increase,crop=${cell_w}:${cell_h}"
    filter="[0:v]${scale_crop}[s0]"
    labels="[s0]"
    for ((k=1; k<grp_n; k++)); do
      filter="${filter};[${k}:v]${scale_crop}[s${k}]"
      labels="${labels}[s${k}]"
    done
  else
    # Fit: first image passes through, rest scaled to match its dimension
    filter="[0:v]null[s0]"
    labels="[s0]"
    for ((k=1; k<grp_n; k++)); do
      if [[ "$mode" == "v" ]]; then
        filter="${filter};[${k}:v]scale=${ref_w}:-2[s${k}]"
      else
        filter="${filter};[${k}:v]scale=-2:${ref_h}[s${k}]"
      fi
      labels="${labels}[s${k}]"
    done
  fi

  if [[ "$mode" == "v" ]]; then
    filter="${filter};${labels}vstack=inputs=${grp_n}"
  else
    filter="${filter};${labels}hstack=inputs=${grp_n}"
  fi

  echo "$filter"
}

# --- Get dimensions of an image ---
img_dims() {
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0 "$1"
}

ncpu=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
JOBS="${PAIRSHOW_JOBS:-$(( ncpu > 12 ? 12 : ncpu ))}"
total_groups=$(( (n + COUNT - 1) / COUNT ))
echo "Compositing ${total_groups} slides (${COUNT} images each, ${JOBS} parallel)..." >&2

compose_slide() {
  local slide="$1" grp_start="$2" grp_end="$3"

  local grp_n=0 inputs=()
  for ((k=grp_start; k<grp_end; k++)); do
    inputs+=( -i "${files[k]}" )
    ((grp_n++))
  done

  local dims ref_w ref_h
  dims="$(img_dims "${files[grp_start]}")"
  ref_w="${dims%%,*}"
  ref_h="${dims##*,}"

  local cell_w="" cell_h=""
  if [[ "$SCALE" == "fill" ]]; then
    if [[ "$MODE" == "v" ]]; then
      cell_w="$screen_w"
      cell_h=$(( screen_h / grp_n ))
    else
      cell_w=$(( screen_w / grp_n ))
      cell_h="$screen_h"
    fi
  fi

  local filter
  filter="$(build_filter "$grp_n" "$MODE" "$ref_h" "$ref_w" "$SCALE" "$cell_w" "$cell_h")"

  local out
  out="$(printf '%s/%04d.jpg' "$tmpdir" "$slide")"
  ffmpeg -nostdin -loglevel error \
    "${inputs[@]}" \
    -filter_complex "$filter" \
    -frames:v 1 -update 1 -q:v 2 "$out"
}

pids=()
slide=0
running=0
for ((i=0; i<n; i+=COUNT)); do
  grp_end=$((i + COUNT))
  (( grp_end > n )) && grp_end=$n

  compose_slide "$slide" "$i" "$grp_end" &
  pids+=($!)
  ((running++))
  ((slide++))

  if (( running >= JOBS )); then
    wait -n 2>/dev/null || true
    ((running--))
    printf '\r  %d/%d' "$((slide - running))" "$total_groups" >&2
  fi
done

# Wait for all remaining jobs
failures=0
for pid in "${pids[@]}"; do
  wait "$pid" 2>/dev/null || ((failures++))
done
printf '\r  %d/%d\n' "$total_groups" "$total_groups" >&2

if (( failures > 0 )); then
  echo "Warning: $failures slide(s) failed to composite." >&2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FS_SCREEN="${PAIRSHOW_FS_SCREEN:-}"

echo "Playing ${slide} slides${FS_SCREEN:+ on screen $FS_SCREEN}..." >&2
mpv --fs \
    ${FS_SCREEN:+--fs-screen="$FS_SCREEN"} \
    --image-display-duration="$DUR" \
    --loop-playlist \
    --keepaspect --background=color --background-color='#FF000000' \
    --script="$SCRIPT_DIR/fade.lua" \
    --script-opts="fade-duration=0.3" \
    "$tmpdir"/*.jpg
