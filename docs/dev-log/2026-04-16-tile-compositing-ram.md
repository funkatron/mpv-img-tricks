# Tile compositing RAM plan (Pass 1–3)

## Shipped

- **Pass 1:** `jobs = min(cpu_cap, tile_cap)` with `cpu_cap = max(1, cpu//2)` and `tile_cap = max(1, _TILE_COMPOSITE_TILE_BUDGET // tile_n)`; `tile_n` uses grid size and (for `--randomize`) `max(grid, min(group_size, path_count))`.
- **Pass 2:** Layouts stored as lightweight `(ccols, crows)` list; slides submitted with bounded in-flight `ThreadPoolExecutor` + `wait(FIRST_COMPLETED)` (no full `slide_specs` materialization).
- **Pass 3:** `_probe_installed_ram_bytes()`, `_ram_cap_candidate_for_logging()` — values appear in `job_schedule` stderr line only; **not** applied to `jobs`.

## Tests

- `tests/test_tile_compositing_caps.py` — cap math and asserts RAM candidate does not clamp jobs.
- `make test` (unit shell + pytest) run locally; `make ci` needs `shellcheck` on PATH.
