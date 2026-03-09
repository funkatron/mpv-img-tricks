#!/usr/bin/env bash

discover_images_to_playlist() {
  local dir="$1"
  local out_file="$2"
  local recursive="${3:-false}"

  if [[ "$recursive" == "true" ]]; then
    find "$dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$out_file"
  else
    find "$dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -V > "$out_file"
  fi
}
