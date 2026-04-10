"""Tile live slideshow via ``scripts/img-effects.sh`` (Bash backend; Python orchestration only here)."""

from __future__ import annotations

import subprocess
from argparse import Namespace

from mpv_img_tricks.paths import get_scripts_dir


def _append_if_value(cmd: list[str], flag: str, value: object | None) -> None:
    if value is None:
        return
    cmd.extend([flag, str(value)])


def _append_if_true(cmd: list[str], flag: str, enabled: bool) -> None:
    if enabled:
        cmd.append(flag)


def _append_diagnostic(cmd: list[str], args: Namespace) -> None:
    _append_if_true(cmd, "--debug", args.debug)
    _append_if_true(cmd, "--quiet", args.quiet)
    _append_if_true(cmd, "--verbose-ffmpeg", args.verbose_ffmpeg)


def build_tile_backend_command(args: Namespace) -> list[str]:
    scripts = get_scripts_dir()
    effect = args.effect or "tile"
    cmd = [str(scripts / "img-effects.sh"), effect, *args.sources]
    cmd.extend(["--duration", str(args.duration)])
    if args.scale_mode != "stretch":
        cmd.extend(["--scale-mode", args.scale_mode])
    cmd.extend(["--instances", str(args.instances)])
    _append_if_value(cmd, "--display", args.display)
    _append_if_value(cmd, "--display-map", args.display_map)
    _append_if_true(cmd, "--master-control", args.master_control)
    _append_if_true(cmd, "--no-master-control", args.no_master_control)
    _append_diagnostic(cmd, args)

    _append_if_value(cmd, "--grid", args.grid)
    _append_if_value(cmd, "--spacing", args.spacing)
    _append_if_value(cmd, "--group-size", args.group_size)
    _append_if_true(cmd, "--randomize", args.randomize)
    _append_if_true(cmd, "--animate-videos", args.animate_videos)
    _append_if_value(cmd, "--encoder", args.encoder)
    _append_if_value(cmd, "--sound", args.sound)
    _append_if_value(cmd, "--sound-trim-db", args.sound_trim_db)
    _append_if_value(cmd, "--max-files", args.max_files)
    _append_if_value(cmd, "--order", args.order)
    if getattr(args, "effect_no_recursive", False):
        _append_if_true(cmd, "--no-recursive", True)
    else:
        _append_if_true(cmd, "--recursive", args.recursive)
    _append_if_true(cmd, "--random-scale", args.random_scale)

    _append_if_true(cmd, "--clear-cache", getattr(args, "clear_cache", False))
    return cmd


def run_tile_live(args: Namespace) -> int:
    return subprocess.run(build_tile_backend_command(args), check=False).returncode
