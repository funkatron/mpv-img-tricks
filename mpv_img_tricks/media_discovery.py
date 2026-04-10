"""Discover image paths from directories, files, or glob patterns (Bash parity with scripts/lib/discovery.sh)."""

from __future__ import annotations

import os
import re
from pathlib import Path

_IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png", ".webp"})


def _is_image_path(p: Path) -> bool:
    return p.suffix.lower() in _IMAGE_SUFFIXES


def _is_glob_pattern(token: str) -> bool:
    return any(c in token for c in "*?[")


def _natural_sort_key(path: str) -> list[str | int]:
    parts: list[str | int] = []
    for segment in path.split(os.sep):
        for t in re.split(r"(\d+)", segment):
            if t.isdigit():
                parts.append(int(t))
            elif t:
                parts.append(t.lower())
    return parts


def _append_from_source(token: str, recursive: bool, acc: list[str]) -> None:
    expanded = os.path.expanduser(token)
    p = Path(expanded)

    if p.is_dir():
        pattern = "**/*" if recursive else "*"
        for f in sorted(p.glob(pattern), key=lambda x: str(x)):
            if f.is_file() and _is_image_path(f):
                acc.append(str(f.resolve()))
        return

    if p.is_file():
        if _is_image_path(p):
            acc.append(str(p.resolve()))
        return

    if _is_glob_pattern(token) or not p.exists():
        glob_dir = Path(os.path.expanduser(os.path.dirname(expanded) or "."))
        glob_base = os.path.basename(expanded)
        it = glob_dir.rglob(glob_base) if recursive else glob_dir.glob(glob_base)
        for f in sorted(it, key=lambda x: str(x)):
            if f.is_file() and _is_image_path(f):
                acc.append(str(f.resolve()))
        return


def _dedupe_preserve_first(lines: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        try:
            key = str(Path(line).resolve())
        except OSError:
            key = line
        if key not in seen:
            seen.add(key)
            out.append(line)
    return out


def _mtime_key(path: str) -> float:
    try:
        return Path(path).stat().st_mtime
    except OSError:
        return 0.0


def discover_sources_to_playlist(
    sources: list[str],
    *,
    order: str,
    recursive: bool,
) -> list[str]:
    """Return sorted, deduplicated image paths for given source tokens."""
    acc: list[str] = []
    for token in sources:
        _append_from_source(token, recursive, acc)
    deduped = _dedupe_preserve_first(acc)
    if order == "natural":
        return sorted(deduped, key=_natural_sort_key)
    if order == "om":
        return sorted(deduped, key=_mtime_key)
    if order == "nm":
        return sorted(deduped, key=_mtime_key, reverse=True)
    raise ValueError(f"invalid order: {order}")
