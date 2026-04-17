"""Live slideshow dispatch: basic and tile in Python pipelines."""

from __future__ import annotations

import shlex
from argparse import Namespace

from mpv_img_tricks.pipelines.basic_slideshow import build_basic_live_preview_commands, run_basic_slideshow
from mpv_img_tricks.pipelines.tile_live import build_tile_backend_command, run_tile_live


def build_live_backend_command(args: Namespace) -> list[str]:
    """Backend argv preview for **dry-run** output."""
    effect = args.effect or "basic"
    if effect == "basic":
        cmds = build_basic_live_preview_commands(args)
        if not cmds:
            return ["mpv"]
        return cmds[0]
    return build_tile_backend_command(args)


def format_live_dry_run(args: Namespace) -> str | None:
    """One or more lines for ``--dry-run``. Returns ``None`` when basic has no discoverable images."""
    effect = args.effect or "basic"
    if effect == "basic":
        cmds = build_basic_live_preview_commands(args)
        if not cmds:
            return None
        return "\n".join(shlex.join(line) for line in cmds)
    return shlex.join(build_live_backend_command(args))


def dispatch_live(args: Namespace) -> int:
    effect = args.effect or "basic"
    if effect == "basic":
        return run_basic_slideshow(args)
    return run_tile_live(args)
