"""Policy for loading ``mpv-scripts/slideshow-bindings.lua`` (parity with ``scripts/lib/mpv_slideshow_bindings.sh``)."""

from __future__ import annotations

import os
from pathlib import Path


def should_load(cli_yes: bool) -> bool:
    """Return False when :envvar:`MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS` is set (overrides CLI)."""
    if os.environ.get("MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS"):
        return False
    return cli_yes


def script_path(repo_root: Path) -> Path:
    """Absolute path to the Lua bindings file."""
    return repo_root / "mpv-scripts" / "slideshow-bindings.lua"
