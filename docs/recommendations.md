# mpv-img-tricks — project recommendations

Forward-looking improvements grounded in the current architecture (Python CLI + Bash backends + mpv/ffmpeg). **Not a roadmap commitment** — use this to prioritize issues and PRs.

**Related:** [discovery.md](discovery.md) (how things work today), [setup.md](setup.md) (install and env).

---

## How to use this doc

- **Impact:** benefit to operators, maintainers, or downstream users.
- **Effort:** S (hours–1 day), M (days), L (week+), XL (major rewrite).
- **Risk:** what could break if done carelessly.

Priorities are opinionated; reorder for your actual goals (e.g. publish to PyPI vs. stay a personal tool).

---

## 1. Operator UX and transparency

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Phase lines for tiled startup** — Before heavy work, print short stderr milestones: ffprobe validation (“checking media 1/N” or start/end summary), optional encoder probe (`--animate-videos`), optional audio prep, then “compositing slides…”. Today many steps are silent (`-loglevel error`, quiet ffprobe loop). | High for trust | S | Low if messages go to stderr and are stable-prefix |
| **Progress that works in pipes** — Keep `\r` updates for TTY; add periodic **newline** progress (every *k* slides or *t* seconds) so `2>&1 \| tee log.txt` and CI logs show movement. | High | S | Low |
| **Optional `--verbose-ffmpeg`** (or tie to `--debug`) — Map compositing `ffmpeg` to `-stats` / higher loglevel when requested; default stays quiet. | Medium | S | Medium: noisier logs may surprise script users |
| **`--quiet` / stable machine mode** — If stderr gets chatty, offer a flag that suppresses phase chatter (keep errors). | Medium | S | Low |
| **Document “why is nothing playing yet?”** — Add a short “Tiled slideshow phases” subsection to [setup.md](setup.md) or discovery §12 appendix (probe → optional sound/encoder → composites → mpv). | High | S | None |

*Includes the earlier tile-specific recommendations; they apply anywhere compositing runs.*

---

## 2. CLI consistency and mental model

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Clarify dual “basic” live paths** — Packaged CLI sends **basic** to `slideshow.sh`; `img-effects.sh` still has `basic_effect` with *different* fullscreen/loop defaults. Document for maintainers, or deprecate direct `img-effects.sh basic` to reduce confusion. | Medium | S (docs) / M (code) | Medium if scripts rely on old behavior |
| **Single place for “default directory”** — `slideshow.sh` falls back to `dead-agent-images/` when `DIR` empty; surprising for generic reuse. Prefer explicit error or env default. | Medium | S | Low |
| **Harmonize discovery recursion** — Basic path uses recursive discovery always; `img-effects` uses `--recursive` flag. Document the difference or align flags. | Medium | M | Behavioral change |

---

## 3. Testing, CI, and quality gates

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Add GitHub Actions (or equivalent)** — `uv sync --frozen` + `./tests/run-unit.sh` on Linux or macOS; install **ripgrep** (`rg`) in the job image (tests require it). | High | S | Low |
| **Document test deps in README/setup** — State `rg` explicitly next to `uv`. | Medium | S | None |
| **CI without sandbox pitfalls** — Jobs that sandboxes `nice` or process substitution can fail; document “run tests in normal container/VM” (already noted in discovery). | Medium | S | None |
| **Expand contract tests** — One test for “phase strings” or `--debug` output; optional test for ffprobe loop mocking N files. | Medium | M | Low |
| **Characterization tests for ffmpeg `eval` replacement** — After moving to argv-based invocation (see §7), assert exact argv fragments for one effect. | Medium | M | Low once refactor exists |
| **Lint shellcheck on `scripts/`** — Optional CI job; fix or suppress intentionally. | Medium | M | Noise until baseline clean |

---

## 4. Security and robustness

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Replace `eval "ffmpeg …"`** in `img-effects.sh` — Build argv arrays or use Python `subprocess.run([...], check=False)` for renders; avoids quoting bugs and reduces injection surface if paths ever come from untrusted input. | High | L | High: touch every effect path; needs golden tests |
| **Audit glob / path handling** — Ensure unusual filenames (spaces, quotes) are handled once shell parsing is simplified. | Medium | M | Medium |

---

## 5. Portability and defaults

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Encoder fallbacks for render effects** — Many paths hardcode **`hevc_videotoolbox`** (macOS). Linux/Windows users may need **`libx264`/`libx265`** auto-detect similar to animated tile path. | High for non-Mac | M–L | Medium: output quality/size drift |
| **Cross-platform screen detection** — Tile path uses macOS `system_profiler` and Linux `xrandr`; document failures and fallback to `--resolution`. Already partially there; surface in UX. | Medium | S | Low |
| **`nice -n 10` on compositing** — Improve CPU sharing on Mac/Linux; may fail or no-op in some containers — document or guard. | Low | S | Low |

---

## 6. Architecture: Python vs Bash (whole project)

**Summary:** Moving **orchestration and reporting** to Python is cheap relative to ffmpeg runtime. Moving **filter graph strings and parallel bash job control** is a **large** maintenance project unless done incrementally.

| Layer | Move to Python? | Notes |
|-------|------------------|-------|
| argparse, validation, `--help`, exit codes | Already there | Extend with JSON progress consumer later |
| Printing phases, progress aggregation | **Yes** — negligibly slower than ffmpeg | Could wrap bash or subprocess ffmpeg directly |
| Subprocess ffmpeg with argv list, no `eval` | **Yes** | Good security/testability win |
| Playlist discovery, sorting (`natural` / `om`) | **Yes** | Duplicated today with `discovery.sh` / img-effects |
| `mpv-pipeline.sh` / multi-instance mpv | **Maybe later** | Shell is fine until you need structured IPC |
| Tile `xstack` graphs, cache layout, bash parallel arrays | **Defer or spike** | High complexity; consider **library** module per effect in Python *after* argv extraction |

**Incremental strategy:** (1) stderr phase + newline progress in Bash; (2) extract one ffmpeg render (`crossfade` or `ken-burns`) to Python subprocess as a pattern; (3) repeat or leave Bash for unmigrated effects.

---

## 7. Observability and debugging

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Unify `--debug`** — Ensure Python forwards debug to backends consistently; document what each layer prints. | Medium | S | Low |
| **Structured log prefix** — e.g. `mpv-img-tricks: phase=probe …` for grep-friendly support. | Medium | S | Low |
| **Optional `--dry-run`** — Print resolved backend argv without `exec` (helps support). | Medium | M | Must not skip validations users rely on |

---

## 8. Packaging and project metadata

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Add `LICENSE`** — Clarify reuse if repo is Public; many orgs won’t touch code without it. | High if public | S | None |
| **`CONTRIBUTING.md`** — Branch policy, test command, “no direct `scripts/` as public API.” | Medium | S | None |
| **`pyproject` optional extras** — e.g. `[project.optional-dependencies] dev = []` for future linters; keep core deps empty if desired. | Low | S | None |
| **Versioning policy** — Even pre-alpha: tag or document breaking CLI policy (README already allows breaks). | Low | S | None |

---

## 9. Repository hygiene

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Large tracked media** — Demo videos under repo root inflate clones; consider **Git LFS**, release assets, or `fixtures/`-only small files. | Medium | M | History rewrite if removing blobs |
| **`.gitignore` vs fixtures** — Broad ignores (`*.jpg`, `*.mp4`) may hide intentional test fixtures; verify `fixtures/` isn’t accidentally ignored for future additions. | Medium | S | Low |
| **`tmp/` in repo** — Ensure not required for runtime; add to `.gitignore` if scratch. | Low | S | None |

---

## 10. Product / feature (optional)

| Recommendation | Impact | Effort | Risk |
|----------------|--------|--------|------|
| **Config file** — Optional `mpv-img-tricks.toml` for defaults (duration, encoder, cache dir) to shorten command lines. | Medium | L | Scope creep |
| **PyPI publish** — Only if others install without git; needs README polish, LICENSE, encoder story for Linux. | High if goal | L | Support burden |

---

## Suggested sequencing (if doing nothing else)

1. **S:** CI workflow + document `rg` + tiled phase lines + newline progress.  
2. **S–M:** LICENSE + CONTRIBUTING + portability note for VideoToolbox.  
3. **M:** Encoder auto-fallback for render effects on non-Mac.  
4. **L:** Remove `eval` ffmpeg from hottest paths or from one representative effect, then expand.

---

## Appendix — What we are *not* recommending (unless goals change)

- **Full rewrite of `img-effects.sh` in Python in one go** — High risk, hard to verify parity; incremental extraction wins.
- **Heavy UI (TUI/GUI)** — Nice-to-have after stable progress and config story.
- **Perfect cross-platform parity** — mpv/ffmpeg behavior varies; document limits first.
