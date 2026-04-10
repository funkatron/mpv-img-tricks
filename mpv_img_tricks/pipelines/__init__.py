"""Pipeline entrypoints (Python orchestration; backends may shell out to scripts or ffmpeg)."""

from __future__ import annotations

from argparse import Namespace

from mpv_img_tricks.pipelines.live import dispatch_live
from mpv_img_tricks.pipelines.plain_render import run_plain_render


def dispatch_plain_render(args: Namespace) -> int:
    return run_plain_render(args)
