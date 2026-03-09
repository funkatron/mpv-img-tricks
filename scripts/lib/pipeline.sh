#!/usr/bin/env bash

build_pipeline_common_args() {
  local duration="$1"
  local fullscreen="$2"
  local loop_mode="$3"
  local scale_mode="$4"
  local instances="$5"
  local master_control="$6"

  PIPELINE_COMMON_ARGS=(
    --duration "$duration"
    --fullscreen "$fullscreen"
    --loop-mode "$loop_mode"
    --scale-mode "$scale_mode"
    --instances "$instances"
    --master-control "$master_control"
  )
}
