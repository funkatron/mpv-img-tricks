"""Auto encode/policy heuristics for large temporal tile grids (TTFF-friendly)."""

from __future__ import annotations

from argparse import Namespace
from collections.abc import Callable

# Per-slide tile count at/above which temporal encodes get cheaper defaults.
_LARGE_TEMPORAL_TILE_THRESHOLD = 40
# Fit temporal output inside this box when resolution was not user-explicit.
_TEMPORAL_FAST_MAX_RESOLUTION = (1920, 1080)


def _fit_inside_box(width: int, height: int, max_w: int, max_h: int) -> tuple[int, int]:
    """Scale down to fit inside max box; keep aspect; even dimensions for encoders."""
    if width <= max_w and height <= max_h:
        return width, height
    scale = min(max_w / max(width, 1), max_h / max(height, 1))
    out_w = max(2, int(round(width * scale / 2.0) * 2))
    out_h = max(2, int(round(height * scale / 2.0) * 2))
    return out_w, out_h


def apply_temporal_encode_policy(
    args: Namespace,
    *,
    cols: int,
    rows: int,
    screen_w: int,
    screen_h: int,
    quiet: bool,
    phase_log: Callable[..., None],
) -> tuple[int, int]:
    """Apply cheaper defaults for large temporal grids; log each auto change.

    Returns possibly-updated ``(screen_w, screen_h)``.
    """
    from mpv_img_tricks.pipelines.tile.motion import _tile_slide_outputs_mp4

    tiles = max(cols * rows, 1)
    if not _tile_slide_outputs_mp4(args):
        return screen_w, screen_h
    if tiles < _LARGE_TEMPORAL_TILE_THRESHOLD:
        return screen_w, screen_h

    reason = "large_temporal_grid"

    # Speed lever for large temporal grids: resolution only.
    # Do not auto-cap motion oversample (thin tiles need auto's 1.5–2.0 or pans look stepped)
    # or force tile_quality=fast (fast_bilinear aliases hard on manga/line-art).

    if not bool(getattr(args, "resolution_explicit", False)):
        max_w, max_h = _TEMPORAL_FAST_MAX_RESOLUTION
        new_w, new_h = _fit_inside_box(screen_w, screen_h, max_w, max_h)
        if (new_w, new_h) != (screen_w, screen_h):
            phase_log(
                f"phase=encode-policy msg=auto_applied resolution={new_w}x{new_h} "
                f"was={screen_w}x{screen_h} reason={reason} tiles={tiles}",
                quiet=quiet,
            )
            screen_w, screen_h = new_w, new_h

    return screen_w, screen_h
