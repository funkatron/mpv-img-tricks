#!/usr/bin/env bash

# Shared image discovery and playlist ordering for slideshow backends.

_mpv_img_tricks_is_glob_pattern() {
  case "$1" in
    *[*?\[]*) return 0 ;;
    *) return 1 ;;
  esac
}

# Append image paths from one source token (directory, file, or glob pattern) to out file.
# Args: token recursive out_file
mpv_img_tricks_append_images_from_source() {
  local token="$1"
  local recursive="$2"
  local out="$3"

  if [[ -d "$token" ]]; then
    if [[ "$recursive" == "true" ]]; then
      find "$token" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null >>"$out"
    else
      find "$token" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null >>"$out"
    fi
    return 0
  fi

  if [[ -f "$token" ]]; then
    case "$token" in
      *.jpg | *.jpeg | *.JPG | *.JPEG | *.png | *.PNG | *.webp | *.WEBP)
        printf '%s\n' "$token" >>"$out"
        ;;
    esac
    return 0
  fi

  if _mpv_img_tricks_is_glob_pattern "$token" || [[ ! -e "$token" ]]; then
    local glob_dir glob_base
    glob_dir="$(dirname "$token")"
    glob_base="$(basename "$token")"
    if [[ "$recursive" == "true" ]]; then
      find "$glob_dir" -name "$glob_base" -type f 2>/dev/null >>"$out"
    else
      find "$glob_dir" -maxdepth 1 -name "$glob_base" -type f 2>/dev/null >>"$out"
    fi
    return 0
  fi

  return 0
}

# Deduplicate path lines by realpath; preserve first occurrence (requires python3).
mpv_img_tricks_dedupe_paths_preserve_first() {
  local infile="$1"
  local outfile="$2"
  python3 - "$infile" "$outfile" <<'PY'
import os
import sys

inp, outp = sys.argv[1], sys.argv[2]
seen = set()
lines_out = []
try:
    with open(inp, encoding="utf-8", errors="surrogateescape") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                key = os.path.realpath(line)
            except OSError:
                key = line
            if key not in seen:
                seen.add(key)
                lines_out.append(line)
except OSError:
    pass
with open(outp, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write("\n".join(lines_out))
    if lines_out:
        f.write("\n")
PY
}

# Sort a newline-separated path list. order: natural | om | nm
mpv_img_tricks_sort_playlist() {
  local input_file="$1"
  local output_file="$2"
  local order="$3"

  case "$order" in
    natural)
      sort -V "$input_file" >"$output_file"
      ;;
    om)
      while IFS= read -r img; do
        [ -n "$img" ] || continue
        mtime=""
        if mtime=$(stat -f '%m' "$img" 2>/dev/null); then
          :
        else
          mtime=$(stat -c '%Y' "$img" 2>/dev/null || echo "0")
        fi
        printf "%s\t%s\n" "$mtime" "$img"
      done <"$input_file" | sort -n -k1,1 | cut -f2- >"$output_file"
      ;;
    nm)
      while IFS= read -r img; do
        [ -n "$img" ] || continue
        mtime=""
        if mtime=$(stat -f '%m' "$img" 2>/dev/null); then
          :
        else
          mtime=$(stat -c '%Y' "$img" 2>/dev/null || echo "0")
        fi
        printf "%s\t%s\n" "$mtime" "$img"
      done <"$input_file" | sort -nr -k1,1 | cut -f2- >"$output_file"
      ;;
    *)
      echo "mpv_img_tricks_sort_playlist: invalid order: $order" >&2
      return 1
      ;;
  esac
}

# Merge multiple sources, dedupe, sort. Args: out_playlist order recursive source...
mpv_img_tricks_discover_sources_to_playlist() {
  local out_playlist="$1"
  local order="$2"
  local recursive="$3"
  shift 3
  local tmp_merge tmp_dedup
  tmp_merge="$(mktemp)"
  tmp_dedup="$(mktemp)"
  local token
  for token in "$@"; do
    mpv_img_tricks_append_images_from_source "$token" "$recursive" "$tmp_merge"
  done
  mpv_img_tricks_dedupe_paths_preserve_first "$tmp_merge" "$tmp_dedup"
  rm -f "$tmp_merge"
  mpv_img_tricks_sort_playlist "$tmp_dedup" "$out_playlist" "$order"
  rm -f "$tmp_dedup"
}

discover_images_to_playlist() {
  local dir="$1"
  local out_file="$2"
  local recursive="${3:-false}"
  mpv_img_tricks_discover_sources_to_playlist "$out_file" "natural" "$recursive" "$dir"
}
