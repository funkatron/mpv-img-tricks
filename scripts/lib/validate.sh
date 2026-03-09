#!/usr/bin/env bash

require_positive_int() {
  local value="$1"
  local name="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
    echo "Error: invalid ${name} value '$value' (expected positive integer)" >&2
    return 1
  fi
}

require_scale_mode() {
  local value="$1"
  case "$value" in
    fit|fill|stretch)
      return 0
      ;;
    *)
      echo "Error: invalid --scale-mode value '$value' (expected fit|fill|stretch)" >&2
      return 1
      ;;
  esac
}
