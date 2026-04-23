# mpv-img-tricks architecture (living)

Use this document when README-level detail is not enough. It describes current runtime flow, key modules, and where to change behavior safely.

For install and day-to-day use, start with [setup.md](setup.md) and [README.md](../README.md).

---

## Runtime routing

```text
slideshow (CLI) -> mpv_img_tricks.cli
                         |
      +------------------+------------------+
      |                                     |
 live/basic                            live/tile
      |                                     |
 basic_slideshow + mpv_pipeline       pipelines.tile_live (Python)
      |
      +-- mpv process orchestration

 live --render (no --effect)
      |
 plain_render (Python + ffmpeg)
```

- `--effect` with `--render` is rejected by CLI.
- `live` is the default subcommand when omitted.

---

## High-signal files

| Path | Role |
|------|------|
| `mpv_img_tricks/cli.py` | CLI args, validation, default subcommand behavior |
| `mpv_img_tricks/pipelines/live.py` | Live dispatch to basic vs tile |
| `mpv_img_tricks/pipelines/basic_slideshow.py` | Basic live flow |
| `mpv_img_tricks/pipelines/tile_live.py` | Tile discovery, validation, compositing, cache, mpv launch |
| `mpv_img_tricks/pipelines/plain_render.py` | Plain render (`--render` without `--effect`) |
| `mpv_img_tricks/mpv_pipeline.py` | mpv argv and multi-instance/master-control helpers |
| `docs/setup.md` | User-facing setup and operations guidance |
| `AGENTS.md` | Internal operator notes for coding agents |

---

## Tile compositing behavior (current)

- Discovery + validation:
  - source discovery in Python
  - `ffprobe` validation with cache `~/.cache/mpv-img-tricks/ffprobe-tile-v5`
- Composite cache:
  - fixed: `~/.cache/mpv-img-tricks/tile-fixed`
  - randomized: `~/.cache/mpv-img-tricks/tile-randomized`
- Worker scheduling:
  - caps: `cpu_cap`, `tile_cap`, optional RAM clamp (`--auto-ram-cap`)
  - logs include `job_schedule ... limit_reason=...`
- Safety/perf controls:
  - `--tile-safe-mode off|warn|auto`
  - `--tile-quality fast|balanced|high`
  - `--tile-hwaccel off|auto` (animated tiles; experimental)

---

## Tests and verification

- Fast targeted:
  - `uv run pytest -q tests/test_tile_compositing_caps.py tests/test_cli_resolution_explicit.py`
- Python suite:
  - `uv run pytest -q tests/`
- Full project checks:
  - `make test`
  - `make ci`

---

## When to edit what

- New CLI flags/help text: `mpv_img_tricks/cli.py`
- Tile runtime/perf/cache behavior: `mpv_img_tricks/pipelines/tile_live.py`
- Basic live behavior: `mpv_img_tricks/pipelines/basic_slideshow.py` and `mpv_img_tricks/mpv_pipeline.py`
- User docs: `README.md` + `docs/setup.md`
- Agent/internal docs: `AGENTS.md` + this file
