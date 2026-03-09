#!/usr/bin/env bash

# Resolve current script path even when invoked through symlinks.
resolve_script_path() {
  local source_path="${1:-${BASH_SOURCE[1]:-}}"
  while [[ -L "$source_path" ]]; do
    local dir
    dir="$(cd "$(dirname "$source_path")" && pwd)"
    source_path="$(readlink "$source_path")"
    [[ "$source_path" != /* ]] && source_path="${dir}/${source_path}"
  done
  echo "$source_path"
}

# Resolve repository root from a script path under scripts/.
resolve_repo_root_from_script() {
  local source_path="$1"
  cd "$(dirname "$source_path")/.." >/dev/null 2>&1 && pwd
}

# Resolve canonical mpv pipeline executable path.
resolve_mpv_pipeline_path() {
  local source_path="$1"
  local repo_root
  repo_root="$(resolve_repo_root_from_script "$source_path")"
  echo "${repo_root}/scripts/mpv-pipeline.sh"
}
