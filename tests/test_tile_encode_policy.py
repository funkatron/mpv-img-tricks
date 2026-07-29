"""Tests for temporal encode policy auto-defaults and logging."""

from __future__ import annotations

from argparse import Namespace

from mpv_img_tricks.pipelines.tile.encode_policy import (
    _LARGE_TEMPORAL_TILE_THRESHOLD,
    apply_temporal_encode_policy,
)


def _args(**kwargs: object) -> Namespace:
    base = dict(
        animate_videos=True,
        tile_motion="off",
        tile_quality="high",
        resolution_explicit=False,
        tile_quality_explicit=False,
    )
    base.update(kwargs)
    return Namespace(**base)


def test_encode_policy_skips_small_grids() -> None:
    logs: list[str] = []
    args = _args()
    w, h = apply_temporal_encode_policy(
        args,
        cols=4,
        rows=4,
        screen_w=3440,
        screen_h=1440,
        quiet=False,
        phase_log=lambda msg, quiet=False: logs.append(msg),
    )
    assert (w, h) == (3440, 1440)
    assert args.tile_quality == "high"
    assert logs == []


def test_encode_policy_auto_applies_for_large_temporal_grid() -> None:
    logs: list[str] = []
    args = _args()
    cols = _LARGE_TEMPORAL_TILE_THRESHOLD
    rows = 1
    w, h = apply_temporal_encode_policy(
        args,
        cols=cols,
        rows=rows,
        screen_w=3440,
        screen_h=1440,
        quiet=False,
        phase_log=lambda msg, quiet=False: logs.append(msg),
    )
    # Quality stays at caller default (high) so line-art stays clean.
    assert args.tile_quality == "high"
    assert w <= 1920 and h <= 1080
    assert any("msg=auto_applied resolution=" in m for m in logs)
    assert not any("tile_quality=" in m for m in logs)
    assert all("reason=large_temporal_grid" in m for m in logs)


def test_encode_policy_respects_explicit_resolution() -> None:
    logs: list[str] = []
    args = _args(
        tile_quality="high",
        tile_quality_explicit=True,
        resolution_explicit=True,
    )
    w, h = apply_temporal_encode_policy(
        args,
        cols=60,
        rows=1,
        screen_w=3440,
        screen_h=1440,
        quiet=False,
        phase_log=lambda msg, quiet=False: logs.append(msg),
    )
    assert args.tile_quality == "high"
    assert (w, h) == (3440, 1440)
    assert logs == []


def test_encode_policy_still_slides_unchanged() -> None:
    logs: list[str] = []
    args = _args(animate_videos=False, tile_motion="off")
    w, h = apply_temporal_encode_policy(
        args,
        cols=60,
        rows=1,
        screen_w=3440,
        screen_h=1440,
        quiet=False,
        phase_log=lambda msg, quiet=False: logs.append(msg),
    )
    assert (w, h) == (3440, 1440)
    assert logs == []
