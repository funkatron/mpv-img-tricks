"""Optional JSON defaults (see docs/setup.md)."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


def config_file_path() -> Path | None:
    env = (os.environ.get("MPV_IMG_TRICKS_CONFIG") or "").strip()
    if env:
        p = Path(env).expanduser()
        return p if p.is_file() else None
    cand = Path.home() / ".config" / "mpv-img-tricks" / "config.json"
    return cand if cand.is_file() else None


def load_config() -> dict[str, Any]:
    path = config_file_path()
    if path is None:
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def live_subparser_defaults(cfg: dict[str, Any]) -> dict[str, Any]:
    """Map config.json keys to `live` subparser destination names."""
    out: dict[str, Any] = {}
    if "duration" in cfg:
        out["duration"] = str(cfg["duration"])
    if "scale_mode" in cfg:
        out["scale_mode"] = str(cfg["scale_mode"])
    if "resolution" in cfg:
        out["resolution"] = str(cfg["resolution"])
    if "fps" in cfg:
        out["fps"] = str(cfg["fps"])
    if "img_per_sec" in cfg:
        out["img_per_sec"] = str(cfg["img_per_sec"])
    if "limit" in cfg:
        out["limit"] = str(cfg["limit"])
    if "quiet" in cfg:
        out["quiet"] = bool(cfg["quiet"])
    if "debug" in cfg:
        out["debug"] = bool(cfg["debug"])
    if "verbose_ffmpeg" in cfg:
        out["verbose_ffmpeg"] = bool(cfg["verbose_ffmpeg"])
    out.setdefault("scale_mode", "fit")
    return out
