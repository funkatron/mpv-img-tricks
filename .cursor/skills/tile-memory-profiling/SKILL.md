---
name: tile-memory-profiling-benchmark
description: >-
  Benchmark tile compositing memory on macOS using one paste script (ffmpeg RSS sampler + /usr/bin/time -l),
  then summarize peaks for tuning grid/resolution and worker limits.
---

# Tile memory benchmark (one-paste workflow)

Use this skill when you need to measure real memory behavior for tile compositing and compare runs across grid/resolution settings.

## What this captures

- Live aggregate ffmpeg RSS every 1s (`ffmpeg_rss_mb`)
- Whole command max RSS from `/usr/bin/time -l` (`maximum resident set size`)
- Run completion status (`exit_code`)
- Resolution + scheduling lines from slideshow logs
- Live terminal output while sampling (via `tee`)

## One paste script (default: smoke benchmark)

Paste this in repo root (`/Users/coj/src/mpv-img-tricks`):

```bash
set -euo pipefail

CMD='slideshow /Volumes/T7-1TB/dbrecovered/image-sessions --effect tile -d 0.001 --fill --random-scale --spacing 32'
SMOKE_MAX=600

run_profile_strict() {
  local tag="$1"; shift
  local args="$*"

  echo "=== $tag ==="
  echo "args: $args"

  # command under /usr/bin/time -l so we get max RSS (smoke set by default)
  /usr/bin/time -l sh -c "$CMD $args --max-files $SMOKE_MAX" >"$tag.out.log" 2>"$tag.time.log" &
  local cmd_pid=$!

  # sample aggregate ffmpeg RSS while command is alive; stream to terminal and log
  (
    while kill -0 "$cmd_pid" 2>/dev/null; do
      ts="$(date +%H:%M:%S)"
      ff_rss_kb="$(ps -axo rss=,comm= | awk '$2 ~ /ffmpeg/ {s+=$1} END {print s+0}')"
      printf "%s ffmpeg_rss_mb=%.1f\n" "$ts" "$(awk "BEGIN {print $ff_rss_kb/1024}")"
      sleep 1
    done
  ) | tee "$tag.mem.log" &
  local mon_pid=$!

  wait "$cmd_pid"
  local rc=$?
  wait "$mon_pid" 2>/dev/null || true
  echo "exit_code=$rc" >"$tag.exit.log"

  echo "--- $tag done (exit=$rc) ---"
}

# Suggested comparison runs (clear-cache for apples-to-apples)
run_profile_strict g20x10_1080 "--grid 20x10 --resolution 1920x1080 --clear-cache"
run_profile_strict g20x10_720  "--grid 20x10 --resolution 1280x720 --clear-cache"

echo
echo "=== summary ==="
for f in g20x10_*.exit.log; do
  printf "%s " "$f"
  cat "$f"
done

for f in g20x10_*.mem.log; do
  peak="$(awk -F'ffmpeg_rss_mb=' 'NF>1{if($2>m)m=$2} END{printf "%.1f", m+0}' "$f")"
  echo "$f peak_ffmpeg_mb=$peak"
done

for f in g20x10_*.time.log; do
  maxrss="$(awk '/maximum resident set size/ {print $1}' "$f" | head -1)"
  echo "$f maxrss_bytes=${maxrss:-missing}"
done

for f in g20x10_*.out.log; do
  echo "== $f =="
  rg "phase=screen|job_schedule|cache_hit|cache_miss|using_resolution_override" "$f" || true
done
```

## Full-set confirm variant (optional, slower)

Use this after smoke benchmarks when you need final full-population confirmation.

```bash
set -euo pipefail

CMD='slideshow /Volumes/T7-1TB/dbrecovered/image-sessions --effect tile -d 0.001 --fill --random-scale --spacing 32'

run_profile_strict() {
  local tag="$1"; shift
  local args="$*"
  /usr/bin/time -l sh -c "$CMD $args" >"$tag.out.log" 2>"$tag.time.log" &
  local cmd_pid=$!
  (
    while kill -0 "$cmd_pid" 2>/dev/null; do
      ts="$(date +%H:%M:%S)"
      ff_rss_kb="$(ps -axo rss=,comm= | awk '$2 ~ /ffmpeg/ {s+=$1} END {print s+0}')"
      printf "%s ffmpeg_rss_mb=%.1f\n" "$ts" "$(awk "BEGIN {print $ff_rss_kb/1024}")"
      sleep 1
    done
  ) | tee "$tag.mem.log" &
  local mon_pid=$!
  wait "$cmd_pid"; local rc=$?
  wait "$mon_pid" 2>/dev/null || true
  echo "exit_code=$rc" >"$tag.exit.log"
}

run_profile_strict full_1080 "--grid 20x10 --resolution 1920x1080 --clear-cache"
run_profile_strict full_720  "--grid 20x10 --resolution 1280x720 --clear-cache"

for f in full_*.mem.log; do
  peak="$(awk -F'ffmpeg_rss_mb=' 'NF>1{if($2>m)m=$2} END{printf "%.1f", m+0}' "$f")"
  echo "$f peak_ffmpeg_mb=$peak"
done
```

## How to interpret

- If `exit_code != 0`, discard that run for tuning.
- If one `*.mem.log` has far fewer samples than others, it likely ended early (interrupted/killed); rerun.
- For large grids where `workers=1`, memory is dominated by one big ffmpeg graph; lowering worker budget will not help much.
- Prefer lower `--resolution` or lower grid size when peak RSS is too high.

## Quick rerun checklist

- Ensure both runs end with `exit_code=0`.
- Ensure each `*.out.log` has `using_resolution_override` for the requested value.
- If one run looks suspiciously short, delete `g20x10_*` logs and rerun both in the same session.

## Notes specific to this repo

- Tile scheduling logs include:
  - `workers`, `cpu_cap`, `tile_cap`, `ram_cap_candidate`, `auto_ram_cap`, `limit_reason`, `tile_budget`
- `ram_cap_candidate` is used when `auto_ram_cap=true` (default); disable with `--no-auto-ram-cap` to compare CPU/tile-only caps.
- `--resolution` explicit override is honored in current main branch, including explicit `1920x1080`.
- Default workflow here is smoke (`--max-files 600`), then optional full-set confirm.
