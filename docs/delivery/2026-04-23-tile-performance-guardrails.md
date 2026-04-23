## TL;DR

This branch adds tile-runtime guardrails so large grids fail less often and degrade more predictably under pressure, while exposing explicit quality/safety controls in the CLI. It also adds an experimental animated-tile hwaccel mode that improved runtime in the recorded benchmark, with a modest peak-RSS increase, and reorganizes docs/log artifacts for clearer long-term maintenance.

## Need

Tile live mode needed clearer controls and safer defaults for high-grid workloads where CPU/RAM pressure can spike, scheduling can overcommit workers, and behavior becomes difficult to reason about. We also needed current architecture docs and benchmark artifacts in stable, discoverable locations so tuning decisions are reproducible.

## Changes

- Added tile performance control flags:
  - `--tile-quality` (`fast` | `balanced` | `high`)
  - `--tile-safe-mode` (`auto` | `warn` | `off`)
  - `--auto-ram-cap` / `--no-auto-ram-cap`
  - `--tile-hwaccel` (`off` | `auto`, experimental for animated tiles)
- Implemented active RAM-aware worker capping in the tile scheduler and surfaced scheduler constraints in `job_schedule` logs via `limit_reason` (for example `cpu`, `tile`, `ram`, or tie combinations).
- Added large-grid safety behavior to downscale in guarded modes to reduce OOM risk and improve predictability on dense layouts.
- Added/updated tests for CLI and compositing cap behavior, including explicit-resolution handling and tile cap logic coverage.
- Reorganized docs:
  - Added a living architecture map at `docs/architecture.md`.
  - Archived discovery content to `docs/archived/discovery.md` and removed the legacy discovery path.
  - Updated cross-references in project docs and operator guidance.
- Archived benchmark artifacts under `docs/archived/benchmarks/2026-04-23/`.
- Updated ignore policy to drop root-level `*.log` artifacts while keeping archived benchmark logs tracked.

## Why

- **Operator control:** explicit knobs (`tile-quality`, `tile-safe-mode`, RAM cap, hwaccel mode) make performance vs quality tradeoffs intentional instead of implicit.
- **Safer scaling:** RAM-aware worker caps plus large-grid guardrails reduce the chance of unstable behavior and memory blowups on big layouts.
- **Actionable observability:** `limit_reason` in scheduler logs explains what actually constrained throughput, making tuning and incident debugging faster.
- **Measured experimentation:** hwaccel remains opt-in/experimental, with benchmark evidence captured and archived to support future tuning decisions.
- **Documentation hygiene:** moving architecture/discovery/benchmark materials into clear living vs archived paths lowers maintenance overhead and onboarding friction.

## Test plan

- `make test`
- Targeted pytest coverage for tile CLI/scheduler behavior:
  - `tests/test_cli_resolution_explicit.py`
  - `tests/test_tile_compositing_caps.py`
- Manual benchmark comparison (archived in `docs/archived/benchmarks/2026-04-23/`) for animated tile hwaccel:
  - hwaccel `off`: `real 101.67s`, `maxrss 5898207232`
  - hwaccel `auto`: `real 94.00s`, `maxrss 6020923392`
  - Interpretation: `auto` was faster in this run, with slightly higher peak RSS.
