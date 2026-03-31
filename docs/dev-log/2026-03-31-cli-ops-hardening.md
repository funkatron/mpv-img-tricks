# Dev log — CLI, backends, CI, default subcommand (2026-03-31)

Internal delivery notes (maintainers). End-user install/use remains [setup.md](../setup.md) and the repo README.

**Commit range (approx.):** `d38179d`–`64159b3` on `main` (plus `a13ed72` license context).

---

## User story

**Extracted** from commits and backlog context; no formal ticket cited.

- **As a** slideshow operator, **I want** a single entrypoint with clearer flags, less noisy ffmpeg, optional dry-runs, and CI that runs unit tests, **so that** I can trust changes and run slideshows/renders without spelunking scripts.

- **As a** daily user of `slideshow`, **I want** to type `slideshow ~/pics` without `live` when that is the main command, **so that** the CLI matches how I think about the tool.

- **Technical / maintainer:** **We want** JSON defaults, argv-safe ffmpeg in `img-effects.sh`, and documentation that matches real behavior **so that** refactors stay testable and onboarding stays honest.

---

## The issue

**Summary:** The project had a growing recommendations backlog (UX, safety, CI, docs) and a CLI that always required `slideshow live …` even though only one subcommand existed. Operators also lacked dry-run, quiet/verbose-ffmpeg plumbing, and consistent phase visibility on slow tile paths.

**Scope — in:** Python CLI (`mpv_img_tricks/cli.py`, `config.py`), bash backends (`slideshow.sh`, `img-effects.sh`, `images-to-video.sh`), unit tests, GitHub Actions (unit + scoped shellcheck), README/setup/discovery/plan updates, default subcommand behavior, docs for that default.

**Scope — out:** R-06 (dual basic paths), R-17 (non-macOS encoder autodetect for render effects), R-24/R-31 per plan; full shellcheck on every script (CI stays scoped).

---

## Acceptance criteria we used

- [x] Unit suite passes: `./tests/run-unit.sh` (`python-cli-spike`, `slideshow-scale-modes`, `img-effects-tile-animation`).
- [x] CLI supports `--dry-run`, `--quiet`, `--verbose-ffmpeg` where implemented; JSON config merge documented.
- [x] `slideshow` may omit `live` when the first token is not another registered subcommand; explicit `DEFAULT_SUBCOMMAND` / `SUBCOMMAND_NAMES` in code.
- [x] Docs (README, setup, discovery) describe the default subcommand and point to `cli.py` for maintainers.
- [x] CI runs frozen env + unit tests + ripgrep; shellcheck runs on the agreed script set.

*Non-regression:* Explicit `slideshow live …` flows remain valid.

---

## How we implemented each part

### 1. Operator UX and backends (tile + shared)

- **What:** `mpv-img-tricks:` phase lines, pipe-friendlier progress, `--quiet` / `--verbose-ffmpeg`, `nice` guard, argv-based ffmpeg helpers (replacing `eval` paths), slideshow requiring a path or `MPV_IMG_TRICKS_DEFAULT_IMAGE_DIR`, recursion flags aligned with discovery.
- **Where:** `scripts/img-effects.sh`, `scripts/slideshow.sh`, `scripts/images-to-video.sh`; diagnostics from `mpv_img_tricks/cli.py`.

### 2. Python CLI and config

- **What:** `load_config()` + `live_subparser_defaults()`; `--dry-run` prints `shlex.join(cmd)`; `DEFAULT_SUBCOMMAND` + `SUBCOMMAND_NAMES` with argv injection before `parse_args`.
- **Where:** `mpv_img_tricks/config.py`, `mpv_img_tricks/cli.py`.

```python
DEFAULT_SUBCOMMAND = "live"
SUBCOMMAND_NAMES: frozenset[str] = frozenset({DEFAULT_SUBCOMMAND})

# main():
argv = sys.argv[1:]
if argv and argv[0] not in SUBCOMMAND_NAMES:
    argv = [DEFAULT_SUBCOMMAND, *argv]
args = parser.parse_args(argv)
```

`build_parser` asserts `DEFAULT_SUBCOMMAND in SUBCOMMAND_NAMES`.

### 3. Tests and CI

- **What:** Contract checks for phase prefix and ffmpeg log lines; CLI spike for `--dry-run` and omitted-`live` routing; GHA for `uv` + `rg` + `./tests/run-unit.sh`; shellcheck scoped to `scripts/lib/*.sh`, `image-effects.sh`, `slideshow.sh`, `images-to-video.sh`.
- **Where:** `tests/unit/*.sh`, `.github/workflows/ci.yml`, `.gitignore`.

### 4. Documentation

- **What:** Setup/plan/README/discovery for prerequisites, JSON config, tiled phases, plan snapshot; then default `live` documented without rewriting every long example.

---

## Why we implemented it this way

| Decision | Options | Why this | Deferred |
|----------|---------|----------|----------|
| Default subcommand vs “only one subcommand” | Inject only when `len(subcommands)==1` | Explicit `DEFAULT_SUBCOMMAND` stays correct when a second subcommand is added | Per-user default override (not asked) |
| Argv prepend vs argparse hacks | Custom `Action` | Small, testable | Parent-level globals before subcommand if ever added |
| Scoped shellcheck | All `scripts/` | Green CI first | Broaden in follow-up |
| Docs keep `live` in long examples | Rewrite all to shorthand | Copy-paste clarity | — |

---

## CLI argv flow

```mermaid
flowchart LR
  A[sys.argv sans prog] B{first in SUBCOMMAND_NAMES?}
  C[parse_args argv]
  D[prepend DEFAULT_SUBCOMMAND]
  A --> B
  B -->|yes| C
  B -->|no| D --> C
```

---

## Verification

- **Smoke:** `uv sync` → `./tests/run-unit.sh`; `uv run slideshow ~/pics --dry-run` vs `slideshow live … --dry-run` (same routing); optional tile run for `mpv-img-tricks: phase=` without `--quiet`.

---

## Residual risk / follow-ups

- **R-17:** Render paths that assume `hevc_videotoolbox` remain awkward off macOS until encoder selection is generalized.
- **New subcommands:** Register every name in `SUBCOMMAND_NAMES` or the first token may be routed into `live` incorrectly.

---

*Story inferred from commits and chat; add issue/PR links here when available.*
