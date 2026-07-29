"""Tile motion helpers for temporal slideshow composites."""

from __future__ import annotations

from argparse import Namespace

_TILE_MOTION_TEMPORAL = frozenset({"ken-burns", "axis-x", "axis-y", "axis-alt"})
# Scales pan extent and zoom ramp for all tile zoompan motion.
_TILE_MOTION_SPEED = 1.0
# zoompan output fps; still-motion tile MP4 encode uses the same -r.
_TILE_MOTION_ZOOMPAN_FPS = 60


def _tile_motion_mode(args: Namespace) -> str:
    return str(getattr(args, "tile_motion", "off"))


def _tile_motion_needs_temporal_slides(args: Namespace) -> bool:
    """Still-image motion modes need looped input + short MP4 per slide."""
    return _tile_motion_mode(args) in _TILE_MOTION_TEMPORAL


def _tile_slide_outputs_mp4(args: Namespace) -> bool:
    """Temporal tile motion (or animated tiles) needs video slide files, not single-frame JPEG."""
    return bool(args.animate_videos) or _tile_motion_needs_temporal_slides(args)


def _pan_progress_expr(dm1: int, *, eased: bool) -> str:
    """Normalized pan progress in [-1, 1] over the clip (linear or smoothstep)."""
    if eased:
        t = f"(on/{dm1})"
        return f"(2*({t})*({t})*(3-2*{t})-1)"
    return f"(2*on/{dm1}-1)"


def _zoompan_linear_pan(
    cell_w: int,
    cell_h: int,
    *,
    duration: float,
    strength: float,
    px: float,
    py: float,
    fixed_zoom: bool = False,
    eased: bool = False,
) -> str:
    """Pan using output frame index ``on``.

    The pan path is centered around the frame midpoint so negative directions
    still move (instead of clamping at x=0/y=0 for the whole clip).
    """
    fps = _TILE_MOTION_ZOOMPAN_FPS
    d = max(2, int(max(float(duration), 1e-6) * fps))
    dm1 = max(d - 1, 1)
    strength = max(float(strength), 0.05)
    px = max(-1.0, min(1.0, float(px))) * _TILE_MOTION_SPEED
    py = max(-1.0, min(1.0, float(py))) * _TILE_MOTION_SPEED
    progress = _pan_progress_expr(dm1, eased=eased)
    if fixed_zoom:
        z_raw = min(1.04 + 0.07 * strength, 1.16)
        z_fix = 1.0 + (z_raw - 1.0) * _TILE_MOTION_SPEED
        z_expr = f"{z_fix:.4f}"
    else:
        z_delta = min(0.06 + 0.12 * strength, 0.28) * _TILE_MOTION_SPEED
        z_expr = f"1+{z_delta:.6f}*on/{dm1}"
    x_pos = f"max(0,min(1,0.5+0.5*{px:.6f}*{progress}))"
    y_pos = f"max(0,min(1,0.5+0.5*{py:.6f}*{progress}))"
    x_expr = f"(iw-iw/zoom)*{x_pos}"
    y_expr = f"(ih-ih/zoom)*{y_pos}"
    return f"zoompan=z='{z_expr}':x='{x_expr}':y='{y_expr}':d={d}:s={cell_w}x{cell_h}:fps={fps}"


def _zoompan_ken_burns(
    cell_w: int,
    cell_h: int,
    tile_index: int,
    *,
    duration: float,
    strength: float,
    parallax: str,
) -> str:
    """Ken Burns-style combined pan + zoom (per-tile variation when parallax is auto)."""
    if parallax == "auto":
        px = (1.0 if (tile_index % 2) == 0 else -1.0) * (0.82 + 0.04 * (tile_index % 5))
        py = (-1.0 if ((tile_index // 2) % 2) == 0 else 1.0) * (0.48 + 0.04 * ((tile_index + 1) % 5))
    else:
        px = 0.88
        py = 0.38
    return _zoompan_linear_pan(
        cell_w, cell_h, duration=duration, strength=strength, px=px, py=py
    )


def _tile_alternate_sign(tile_index: int) -> float:
    """Even-index tiles drift negative (left/up); odd-index tiles drift positive (right/down)."""
    return -1.0 if (tile_index % 2) == 0 else 1.0


def _parallax_multiplier(tile_index: int, parallax: str) -> float:
    """Keep mode direction stable; only vary magnitude when parallax is auto."""
    if parallax != "auto":
        return 1.0
    return 0.84 + 0.04 * (tile_index % 5)


# Ken Burns runs a zoompan chain per animated tile; small grids can afford all tiles.
# Above this, keep a 1/4 sample so huge xstack filter graphs stay manageable.
_KEN_BURNS_ANIMATE_ALL_TILES_UP_TO = 16


def _ken_burns_animated_indices(tile_count: int) -> set[int]:
    """Which inputs get zoompan for Ken Burns (others stay still in the grid)."""
    if tile_count <= 0:
        return set()
    if tile_count <= _KEN_BURNS_ANIMATE_ALL_TILES_UP_TO:
        return set(range(tile_count))
    animated = max(1, tile_count // 4)
    if animated >= tile_count:
        return set(range(tile_count))
    return {(k * tile_count) // animated for k in range(animated)}


def _zoompan_axis_x(
    cell_w: int,
    cell_h: int,
    tile_index: int,
    cols: int,
    *,
    duration: float,
    strength: float,
    parallax: str,
) -> str:
    """Horizontal drift; adjacent tiles move in opposite directions."""
    m = _parallax_multiplier(tile_index, parallax)
    px = _tile_alternate_sign(tile_index) * 0.9 * m
    py = 0.0
    return _zoompan_linear_pan(
        cell_w,
        cell_h,
        duration=duration,
        strength=strength,
        px=px,
        py=py,
        fixed_zoom=True,
    )


def _zoompan_axis_y(
    cell_w: int,
    cell_h: int,
    tile_index: int,
    cols: int,
    *,
    duration: float,
    strength: float,
    parallax: str,
) -> str:
    """Vertical drift; adjacent tiles move in opposite directions."""
    m = _parallax_multiplier(tile_index, parallax)
    px = 0.0
    py = _tile_alternate_sign(tile_index) * 0.9 * m
    return _zoompan_linear_pan(
        cell_w,
        cell_h,
        duration=duration,
        strength=strength,
        px=px,
        py=py,
        fixed_zoom=True,
    )


def _zoompan_axis_alt(
    cell_w: int,
    cell_h: int,
    tile_index: int,
    cols: int,
    *,
    duration: float,
    strength: float,
    parallax: str,
) -> str:
    """Diagonal drift; adjacent tiles move in opposite directions on both axes."""
    m = _parallax_multiplier(tile_index, parallax)
    s = _tile_alternate_sign(tile_index)
    px = s * 0.9 * m
    py = s * 0.9 * m
    return _zoompan_linear_pan(
        cell_w,
        cell_h,
        duration=duration,
        strength=strength,
        px=px,
        py=py,
        fixed_zoom=True,
    )

