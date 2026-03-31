# Execution plan — recommendations backlog

This document turns **[recommendations.md](recommendations.md)** into an implementable sequence. **Source of truth for what you prioritized** is the checkbox state in `recommendations.md` ( **`R-xx`** ids). Update this plan when scope or order changes.

**Explicitly not in scope** (unchecked in recommendations as of last sync): **R-06**, **R-17**, **R-24**, **R-31**.

**R-30 note:** Config file is **wanted**, but **not TOML** — use **JSON** (e.g. `~/.config/mpv-img-tricks/config.json` or `MPV_IMG_TRICKS_CONFIG`), merged under normal CLI precedence (CLI overrides file).

---

## Current repo status (implementation snapshot)

**Landed in tree:** Phase-style `mpv-img-tricks:` stderr lines (**R-01** / **R-21**), newline-friendly progress (**R-02**), `--quiet` / `--verbose-ffmpeg` plumbed (**R-03** / **R-04**), tiled phases documented (**R-05**), slideshow default dir + recursion flags (**R-07** / **R-08**), GHA unit job + scoped shellcheck + `rg` (**R-09** / **R-14**), `.gitignore` for `tmp/` and trackable `fixtures/` (**R-28** / **R-29**), test/docs notes on CI vs sandbox (**R-10** / **R-11**), contract tests including phase prefix and ffmpeg argv logging (**R-12** / **R-13**), argv-style ffmpeg in `img-effects.sh` (**R-15**), `nice` guard (**R-19**), `--dry-run` + JSON config defaults (**R-22** / **R-30**), screen/resolution and versioning notes (**R-18** / **R-26** / **R-27**), optional `dev` extra in `pyproject.toml` (**R-25**).

**Still explicit non-goals / follow-ups:** **R-06** (dual basic paths), **R-17** (encoder fallbacks off macOS), **R-24**, **R-31** per [recommendations.md](recommendations.md). **R-20** (forward `--debug` everywhere): confirm parity across `images-to-video.sh` if gaps appear.

---

## Phases (suggested order)

### Phase A — Baseline and hygiene (fast merges)

| R-xx | Deliverable |
|------|-------------|
| **R-23** | Commit `LICENSE` (**BSD-3-Clause**). |
| **R-09** | Commit `.github/workflows/ci.yml`: `uv sync --frozen` + `./tests/run-unit.sh`; install **ripgrep**. |
| **R-14** | Keep shellcheck job; tune (`continue-on-error`, paths, or fix findings) so **main stays green** or policy is explicit. |
| **R-28** | `.gitignore`: ensure `fixtures/` stay trackable; document if negation rules change. |
| **R-29** | Ignore `tmp/` scratch dir. |
| **R-10** | README + [setup.md](setup.md): **`rg` required** for `./tests/run-unit.sh`. |
| **R-11** | Document: run tests in normal VM/CI (not sandboxes that block `nice` / process substitution). |

### Phase B — Operator UX (tile / compositing)

| R-xx | Deliverable |
|------|-------------|
| **R-21** | Prefix stderr lines: `mpv-img-tricks: …` (phases + progress). |
| **R-01** | Phase lines: ffprobe sweep start/end, encoder probe (animate), audio prep, compositing start. |
| **R-02** | TTY `\r` plus **newline** progress every *N* slides or *T* seconds (pipe-friendly). |
| **R-04** | `--quiet`: suppress phase chatter; still print errors. Plumbed from **Python CLI → backends**. |
| **R-03** | **`--verbose-ffmpeg`** and/or tie compositing **ffmpeg** log/stats to **`--debug`**. |
| **R-05** | “Tiled slideshow phases” in **setup.md** and/or **discovery.md** §12. |
| **R-19** | Guard **`nice -n 10`**: if `nice` unusable, run **ffmpeg** without it. |

### Phase C — CLI and consistency

| R-xx | Deliverable |
|------|-------------|
| **R-07** | Remove surprise default dir in `slideshow.sh`; require path or **`MPV_IMG_TRICKS_DEFAULT_IMAGE_DIR`**. |
| **R-08** | Align discovery defaults (e.g. **`img-effects`** recursive default **true** to match basic live, **or** document + add **`slideshow --no-recursive`** for images — pick one and document). |
| **R-20** | Ensure **`--debug`** is forwarded consistently to **all** backends (`slideshow.sh`, `img-effects.sh`, `images-to-video.sh`). |
| **R-22** | **`--dry-run`**: print resolved backend argv; no `exec`/`mpv`/`ffmpeg` side effects where feasible. |
| **R-30** | Load **JSON** defaults; merge with argparse (CLI wins). |

### Phase D — Security / robustness (larger)

| R-xx | Deliverable |
|------|-------------|
| **R-15** | Replace **`eval "ffmpeg …"`** in `img-effects.sh` with **argv-safe** invocation; shared helper + **mem/thread** args as array. |
| **R-13** | Characterization test: assert **ffmpeg argv** fragment for one effect after R-15. |
| **R-16** | Path audit (spaces/special chars) once R-15 lands. |

### Phase E — Tests and docs polish

| R-xx | Deliverable |
|------|-------------|
| **R-12** | Contract test: phase string or `--debug` output line when not **quiet**. |
| **R-18** | Document screen detection limits + **`--resolution`** fallback (setup/discovery). |
| **R-25** | `pyproject.toml` **`[project.optional-dependencies]`** `dev` (placeholders OK). |
| **R-26** | Short **versioning / breaking CLI** note (README or `docs/`). |
| **R-27** | Document large media / **LFS** / release-asset strategy (no mandatory history rewrite). |

---

## Judgment calls (trust defaults)

- **Order:** Ship **Phase A** before refactors so CI guards **R-15** and **R-12**/`R-13**.
- **R-14:** Prefer **making shellcheck pass** or **scoping** to `scripts/lib` first over a permanently red job.
- **R-22:** Dry-run may still run lightweight validation (existence of scripts); document what **is** / **is not** executed.
- **R-30:** Keep schema small (duration, resolution, flags) until usage proves need for more.

---

## After completion

- Uncheck or archive **R-xx** items in [recommendations.md](recommendations.md) when done, or move to a shipped section.
- Optionally add a one-line “Last implemented” date at the bottom of this file.
