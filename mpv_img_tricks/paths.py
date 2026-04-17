"""Resolve repository root and the `scripts/` backend directory."""

from __future__ import annotations

import os
from pathlib import Path


def _looks_like_repo(path: Path) -> bool:
    return (path / "scripts" / "slideshow.sh").is_file()


def get_repo_root() -> Path:
    """Return the checkout root that contains ``scripts/slideshow.sh``.

    Search order:

    1. :envvar:`MPV_IMG_TRICKS_ROOT` if set and valid.
    2. Parents of this package (editable installs live inside the repo).
    3. :func:`pathlib.Path.cwd` and its parents.
    """
    env_root = os.environ.get("MPV_IMG_TRICKS_ROOT")
    if env_root:
        p = Path(env_root).expanduser().resolve()
        if _looks_like_repo(p):
            return p
        msg = f"MPV_IMG_TRICKS_ROOT is set but does not look like mpv-img-tricks: {p}"
        raise FileNotFoundError(msg)

    here = Path(__file__).resolve().parent
    for d in (here, *here.parents):
        if _looks_like_repo(d):
            return d

    cwd = Path.cwd().resolve()
    for d in (cwd, *cwd.parents):
        if _looks_like_repo(d):
            return d

    raise FileNotFoundError(
        "Cannot find mpv-img-tricks repo root (expected scripts/slideshow.sh). "
        "Run from the repository, install editable with `uv sync`, or set MPV_IMG_TRICKS_ROOT."
    )


def get_scripts_dir() -> Path:
    """Directory containing legacy helper scripts (e.g. ``slideshow.sh`` / ``images-to-video.sh``)."""
    override = os.environ.get("MPV_IMG_TRICKS_SCRIPTS_DIR")
    if override:
        return Path(override).expanduser().resolve()
    return get_repo_root() / "scripts"
