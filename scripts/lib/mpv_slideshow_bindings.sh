#!/usr/bin/env bash
# Shared policy for mpv-scripts/slideshow-bindings.lua (slideshow key bindings).

# Relative to repository root.
MPV_IMG_TRICKS_SLIDESHOW_BINDINGS_RELPATH="mpv-scripts/slideshow-bindings.lua"

# Usage: mpv_img_tricks_slideshow_bindings_should_load <cli_yes_no>
# cli_yes_no: from --use-slideshow-bindings (mpv-pipeline.sh), or "yes" for
# direct mpv launches. If MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS
# is non-empty, loading is disabled (overrides CLI).
mpv_img_tricks_slideshow_bindings_should_load() {
  local cli_toggle="${1:-yes}"
  if [[ -n "${MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS:-}" ]]; then
    return 1
  fi
  [[ "$cli_toggle" == "yes" || "$cli_toggle" == "true" ]]
}

mpv_img_tricks_slideshow_bindings_script_path() {
  local repo_root="$1"
  echo "${repo_root}/${MPV_IMG_TRICKS_SLIDESHOW_BINDINGS_RELPATH}"
}
