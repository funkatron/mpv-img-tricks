"""Filter graph builders for tile composites."""

from __future__ import annotations

from .motion import (
    _TILE_MOTION_TEMPORAL,
    _ken_burns_animated_indices,
    _zoompan_axis_alt,
    _zoompan_axis_x,
    _zoompan_axis_y,
    _zoompan_ken_burns,
)


def _round_even(value: float) -> int:
    return max(2, int(round(float(value) / 2.0) * 2))


def _motion_sample_scale(tile_motion_oversample: str, *, cell_w: int, cell_h: int) -> float:
    raw = str(tile_motion_oversample).strip().lower()
    if raw and raw != "auto":
        try:
            return max(1.0, float(raw))
        except ValueError:
            return 1.0
    # Auto mode: increase sampling for small tiles to reduce visible stepping.
    short_edge = max(1, min(cell_w, cell_h))
    if short_edge <= 220:
        return 2.0
    if short_edge <= 420:
        return 1.5
    return 1.0


def _tile_cell_filter(cell_w: int, cell_h: int, scale_mode: str, *, tile_quality: str) -> str:
    scale_flags = {
        "fast": "fast_bilinear",
        "balanced": "bicubic",
        "high": "lanczos",
    }[tile_quality]
    if scale_mode == "fill":
        return (
            f"scale={cell_w}:{cell_h}:force_original_aspect_ratio=increase:flags={scale_flags},"
            f"crop={cell_w}:{cell_h}"
        )
    return (
        # Keep fit-scaled inputs chroma-safe (even dimensions) so odd-sized cells
        # don't make pad reject slightly larger rounded scale outputs.
        f"scale={cell_w}:{cell_h}:force_original_aspect_ratio=decrease:force_divisible_by=2:flags={scale_flags},"
        f"pad={cell_w}:{cell_h}:(ow-iw)/2:(oh-ih)/2:black"
    )


def _tile_motion_downsample_filter(cell_w: int, cell_h: int, *, tile_quality: str) -> str:
    scale_flags = {
        "fast": "fast_bilinear",
        "balanced": "bicubic",
        "high": "lanczos",
    }[tile_quality]
    return f"scale={cell_w}:{cell_h}:flags={scale_flags}"


def _build_filter(
    *,
    cols: int,
    rows: int,
    screen_w: int,
    screen_h: int,
    spacing: int,
    scale_mode: str,
    tile_quality: str,
    tile_motion: str = "off",
    tile_parallax: str = "off",
    tile_motion_strength: float = 1.0,
    tile_motion_oversample: str = "auto",
    duration: float = 2.0,
) -> tuple[str, int]:
    tile_count = cols * rows
    usable_w = screen_w - spacing * (cols - 1)
    usable_h = screen_h - spacing * (rows - 1)
    if usable_w <= 0 or usable_h <= 0:
        raise ValueError("spacing too large for selected grid/screen")
    cell_w = usable_w // cols
    cell_h = usable_h // rows
    cell = _tile_cell_filter(cell_w, cell_h, scale_mode, tile_quality=tile_quality)
    sample_scale = _motion_sample_scale(tile_motion_oversample, cell_w=cell_w, cell_h=cell_h)
    sample_w = _round_even(cell_w * sample_scale)
    sample_h = _round_even(cell_h * sample_scale)
    motion_cell = _tile_cell_filter(sample_w, sample_h, scale_mode, tile_quality=tile_quality)
    post_motion = _tile_motion_downsample_filter(cell_w, cell_h, tile_quality=tile_quality)
    parts: list[str] = []
    motion_active = tile_motion in _TILE_MOTION_TEMPORAL
    ken_burns_active = tile_motion == "ken-burns"
    ken_burns_animated = _ken_burns_animated_indices(tile_count) if ken_burns_active else set()
    for i in range(tile_count):
        if motion_active:
            if tile_motion == "ken-burns":
                if i not in ken_burns_animated:
                    parts.append(f"[{i}:v]{cell}[m{i}]")
                    continue
                zp = _zoompan_ken_burns(
                    sample_w,
                    sample_h,
                    i,
                    duration=float(duration),
                    strength=float(tile_motion_strength),
                    parallax=str(tile_parallax),
                )
            elif tile_motion == "axis-x":
                zp = _zoompan_axis_x(
                    sample_w,
                    sample_h,
                    i,
                    cols,
                    duration=float(duration),
                    strength=float(tile_motion_strength),
                    parallax=str(tile_parallax),
                )
            elif tile_motion == "axis-y":
                zp = _zoompan_axis_y(
                    sample_w,
                    sample_h,
                    i,
                    cols,
                    duration=float(duration),
                    strength=float(tile_motion_strength),
                    parallax=str(tile_parallax),
                )
            else:
                zp = _zoompan_axis_alt(
                    sample_w,
                    sample_h,
                    i,
                    cols,
                    duration=float(duration),
                    strength=float(tile_motion_strength),
                    parallax=str(tile_parallax),
                )
            # Normalize to sampled tile space while preserving aspect, then animate,
            # then downsample to final tile size.
            parts.append(f"[{i}:v]{motion_cell},{zp},{post_motion}[m{i}]")
        else:
            parts.append(f"[{i}:v]{cell}[s{i}]")
    stack_inputs = "".join(f"[{'m' if motion_active else 's'}{i}]" for i in range(tile_count))
    layout = "|".join(
        f"{(i % cols) * (cell_w + spacing)}_{(i // cols) * (cell_h + spacing)}" for i in range(tile_count)
    )
    if tile_count == 1:
        src0 = "m0" if motion_active else "s0"
        parts.append(f"[{src0}]copy[grid];[grid]pad={screen_w}:{screen_h}:(ow-iw)/2:(oh-ih)/2:black[out]")
    else:
        parts.append(
            f"{stack_inputs}xstack=inputs={tile_count}:layout={layout}:fill=black[grid];[grid]pad={screen_w}:{screen_h}:(ow-iw)/2:(oh-ih)/2:black[out]"
        )
    return ";".join(parts), tile_count


def _filter_for_still_jpeg_encode(filter_complex: str) -> str:
    """xstack+pad often yields yuv444p; MJPEG (.jpg) needs a JPEG-friendly pix fmt or encode fails."""
    if not filter_complex.endswith("[out]"):
        return filter_complex
    stem = filter_complex[: -len("[out]")]
    return f"{stem}[pjfmt];[pjfmt]format=yuvj420p[out]"

