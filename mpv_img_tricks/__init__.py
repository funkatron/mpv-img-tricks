"""Python façade for mpv-img-tricks: CLI entrypoints and helpers to locate Bash backends."""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

from mpv_img_tricks.cli import main
from mpv_img_tricks.paths import get_repo_root, get_scripts_dir

try:
    __version__ = version("mpv-img-tricks")
except PackageNotFoundError:
    __version__ = "0.0.0"

__all__ = ["__version__", "main", "get_repo_root", "get_scripts_dir"]
