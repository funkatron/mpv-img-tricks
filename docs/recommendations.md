# mpv-img-tricks — project recommendations

Forward-looking improvements grounded in the current architecture (Python CLI + Bash backends + mpv/ffmpeg). **Not a roadmap commitment** — use this to prioritize issues and PRs.

**Related:** [discovery.md](discovery.md) (how things work today), [setup.md](setup.md) (install and env). **Execution order:** [plan.md](plan.md) (phases and implementation snapshot).

---

## How to use this doc

- **IDs:** Each actionable item has a stable **`R-xx`** id for issues, PRs, and chat.
- **Checkboxes:** Toggle `[x]` / `[ ]` in your editor to track what you plan to do.
- **Pre-selected:** Items marked **[x]** below match **High impact** and **S** effort (hours to ~1 day) per the table columns. *“High if public”* (e.g. LICENSE) is included; uncheck if the repo stays private-only.
- **Impact:** benefit to operators, maintainers, or downstream users.
- **Effort:** S (hours–1 day), M (days), L (week+), XL (major rewrite).
- **Risk:** what could break if done carelessly.

Priorities are opinionated; reorder for your actual goals (e.g. publish to PyPI vs. stay a personal tool).

---

## 1. Operator UX and transparency

- [x] **R-01** — **Phase lines for tiled startup** — Before heavy work, print short stderr milestones: ffprobe validation (“checking media 1/N” or start/end summary), optional encoder probe (`--animate-videos`), optional audio prep, then “compositing slides…”. Today many steps are silent (`-loglevel error`, quiet ffprobe loop). *Impact: High for trust · Effort: S · Risk: Low if messages go to stderr and use a stable prefix.*
- [x] **R-02** — **Progress that works in pipes** — Keep `\r` updates for TTY; add periodic **newline** progress (every *k* slides or *t* seconds) so `2>&1 | tee log.txt` and CI logs show movement. *Impact: High · Effort: S · Risk: Low.*
- [x] **R-03** — **Optional `--verbose-ffmpeg`** (or tie to `--debug`) — Map compositing `ffmpeg` to `-stats` / higher loglevel when requested; default stays quiet. *Impact: Medium · Effort: S · Risk: Medium (noisier logs may surprise script users).*
- [x] **R-04** — **`--quiet` / stable machine mode** — If stderr gets chatty, offer a flag that suppresses phase chatter (keep errors). *Impact: Medium · Effort: S · Risk: Low.*
- [x] **R-05** — **Document “why is nothing playing yet?”** — Add a short “Tiled slideshow phases” subsection to [setup.md](setup.md) or discovery §12 appendix (probe → optional sound/encoder → composites → mpv). *Impact: High · Effort: S · Risk: None.*

*R-01–R-05 include the tile-specific UX ideas; they apply anywhere compositing runs.*

---

## 2. CLI consistency and mental model

- [ ] **R-06** — **Clarify dual “basic” live paths** — Packaged CLI sends **basic** to `slideshow.sh`; `img-effects.sh` still has `basic_effect` with *different* fullscreen/loop defaults. Document for maintainers, or deprecate direct `img-effects.sh basic` to reduce confusion. *Impact: Medium · Effort: S (docs) / M (code) · Risk: Medium if scripts rely on old behavior.*
- [x] **R-07** — **Single place for “default directory”** — `slideshow.sh` falls back to `dead-agent-images/` when `DIR` empty; surprising for generic reuse. Prefer explicit error or env default. *Impact: Medium · Effort: S · Risk: Low.*
- [x] **R-08** — **Harmonize discovery recursion** — Basic path uses recursive discovery always; `img-effects` uses `--recursive` flag. Document the difference or **align flags**. *Impact: Medium · Effort: M · Risk: Behavioral change.*

---

## 3. Testing, CI, and quality gates

- [x] **R-09** — **Add GitHub Actions (or equivalent)** — `uv sync --frozen` + `./tests/run-unit.sh` on Linux or macOS; install **ripgrep** (`rg`) in the job image (tests require it). *Impact: High · Effort: S · Risk: Low.*
- [x] **R-10** — **Document test deps in README/setup** — State `rg` explicitly next to `uv`. *Impact: Medium · Effort: S · Risk: None.*
- [x] **R-11** — **CI without sandbox pitfalls** — Jobs that sandboxes `nice` or process substitution can fail; document “run tests in normal container/VM” (already noted in discovery). *Impact: Medium · Effort: S · Risk: None.*
- [x] **R-12** — **Expand contract tests** — One test for “phase strings” or `--debug` output; optional test for ffprobe loop mocking N files. *Impact: Medium · Effort: M · Risk: Low.*
- [x] **R-13** — **Characterization tests for ffmpeg `eval` replacement** — After moving to argv-based invocation (see §4), assert exact argv fragments for one effect. *Impact: Medium · Effort: M · Risk: Low once refactor exists.*
- [x] **R-14** — **Lint shellcheck on `scripts/`** — Optional CI job; fix or suppress intentionally. *Impact: Medium · Effort: M · Risk: Noise until baseline clean.*

---

## 4. Security and robustness

- [x] **R-15** — **Replace `eval "ffmpeg …"`** in `img-effects.sh` — Build argv arrays or use Python `subprocess.run([...], check=False)` for renders; avoids quoting bugs and reduces injection surface if paths ever come from untrusted input. *Impact: High · Effort: L · Risk: High (touches every effect path; needs golden tests).*
- [x] **R-16** — **Audit glob / path handling** — Ensure unusual filenames (spaces, quotes) are handled once shell parsing is simplified. *Impact: Medium · Effort: M · Risk: Medium.*

---

## 5. Portability and defaults

- [ ] **R-17** — **Encoder fallbacks for render effects** — Many paths hardcode **`hevc_videotoolbox`** (macOS). Linux/Windows users may need **`libx264`/`libx265`** auto-detect similar to animated tile path. *Impact: High for non-Mac · Effort: M–L · Risk: Medium (output quality/size drift).*
- [x] **R-18** — **Cross-platform screen detection** — Tile path uses macOS `system_profiler` and Linux `xrandr`; document failures and fallback to `--resolution`. Already partially there; surface in UX. *Impact: Medium · Effort: S · Risk: Low.*
- [x] **R-19** — **`nice -n 10` on compositing** — Improve CPU sharing on Mac/Linux; may fail or no-op in some containers — document or guard. *Impact: Low · Effort: S · Risk: Low.*

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

**Incremental strategy (maps to R-01 / R-02 and later R-15):** (1) stderr phase + newline progress in Bash tile path; (2) extend Python **`plain_render`** / pipelines for more export modes as needed; (3) optionally port **`img-effects.sh`** tile logic to Python in slices.

---

## 7. Observability and debugging

- [x] **R-20** — **Unify `--debug`** — Ensure Python forwards debug to backends consistently; document what each layer prints. *Impact: Medium · Effort: S · Risk: Low.*
- [x] **R-21** — **Structured log prefix** — e.g. `mpv-img-tricks: phase=probe …` for grep-friendly support. *Impact: Medium · Effort: S · Risk: Low.*
- [x] **R-22** — **Optional `--dry-run`** — Print resolved backend argv without `exec` (helps support). *Impact: Medium · Effort: M · Risk: Must not skip validations users rely on.*

---

## 8. Packaging and project metadata

- [x] **R-23** — **Add `LICENSE`** — Clarify reuse if repo is Public; many orgs won’t touch code without it. *Impact: High if public · Effort: S · Risk: None.*
- [ ] **R-24** — **`CONTRIBUTING.md`** — Branch policy, test command, “no direct `scripts/` as public API.” *Impact: Medium · Effort: S · Risk: None.*
- [x] **R-25** — **`pyproject` optional extras** — e.g. `[project.optional-dependencies] dev = []` for future linters; keep core deps empty if desired. *Impact: Low · Effort: S · Risk: None.*
- [x] **R-26** — **Versioning policy** — Even pre-alpha: tag or document breaking CLI policy (README already allows breaks). *Impact: Low · Effort: S · Risk: None.*

---

## 9. Repository hygiene

- [x] **R-27** — **Large tracked media** — Demo videos under repo root inflate clones; consider **Git LFS**, release assets, or `fixtures/`-only small files. *Impact: Medium · Effort: M · Risk: History rewrite if removing blobs.*
- [x] **R-28** — **`.gitignore` vs fixtures** — Broad ignores (`*.jpg`, `*.mp4`) may hide intentional test fixtures; verify `fixtures/` isn’t accidentally ignored for future additions. *Impact: Medium · Effort: S · Risk: Low.*
- [x] **R-29** — **`tmp/` in repo** — Ensure not required for runtime; add to `.gitignore` if scratch. *Impact: Low · Effort: S · Risk: None.*

---

## 10. Product / feature (optional)

- [x] **R-30** — **Config file** — Optional `mpv-img-tricks.toml` for defaults (duration, encoder, cache dir) to shorten command lines. *Impact: Medium · Effort: L · Risk: Scope creep.* **NOT TOML, but YES**
- [ ] **R-31** — **PyPI publish** — Only if others install without git; needs README polish, LICENSE, encoder story for Linux. *Impact: High if goal · Effort: L · Risk: Support burden.*

---

## Suggested sequencing (if doing nothing else)

1. **S:** **R-09** (CI) + **R-10** (document `rg`) + **R-01** / **R-02** (tiled progress) + **R-05** (docs).
2. **S–M:** **R-23** (LICENSE) + **R-24** (CONTRIBUTING) + **R-17**-style portability note for VideoToolbox (see **R-17**).
3. **M:** **R-17** (encoder auto-fallback for render effects on non-Mac).
4. **L:** **R-15** (remove `eval` ffmpeg from hottest paths or one representative effect, then expand).

---

## Appendix — What we are *not* recommending (unless goals change)

- **Full rewrite of `img-effects.sh` in Python in one go** — High risk, hard to verify parity; incremental extraction wins.
- **Heavy UI (TUI/GUI)** — Nice-to-have after stable progress and config story.
- **Perfect cross-platform parity** — mpv/ffmpeg behavior varies; document limits first.
