"""Filter graph builders for tile composites."""

from __future__ import annotations

from .motion import (
    _TILE_MOTION_TEMPORAL,
    _TILE_MOTION_ZOOMPAN_FPS,
    _ken_burns_animated_indices,
    _zoompan_ken_burns,
    _zoompan_parallax,
)


def _round_even(value: float) -> int:
    return max(2, int(round(float(value) / 2.0) * 2))


def _motion_sample_scale(*, cell_w: int, cell_h: int) -> float:
    """Auto oversample for small tiles to reduce visible pan stepping."""
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
    duration: float = 2.0,
    input_is_video: list[bool] | None = None,
) -> tuple[str, int]:
    tile_count = cols * rows
    usable_w = screen_w - spacing * (cols - 1)
    usable_h = screen_h - spacing * (rows - 1)
    if usable_w <= 0 or usable_h <= 0:
        raise ValueError("spacing too large for selected grid/screen")
    cell_w = usable_w // cols
    cell_h = usable_h // rows
    cell = _tile_cell_filter(cell_w, cell_h, scale_mode, tile_quality=tile_quality)
    sample_scale = _motion_sample_scale(cell_w=cell_w, cell_h=cell_h)
    sample_w = _round_even(cell_w * sample_scale)
    sample_h = _round_even(cell_h * sample_scale)
    motion_cell = _tile_cell_filter(sample_w, sample_h, scale_mode, tile_quality=tile_quality)
    post_motion = _tile_motion_downsample_filter(cell_w, cell_h, tile_quality=tile_quality)
    parts: list[str] = []
    tile_labels: list[str] = []
    motion_active = tile_motion in _TILE_MOTION_TEMPORAL
    ken_burns_active = tile_motion == "ken-burns"
    ken_burns_animated = _ken_burns_animated_indices(tile_count) if ken_burns_active else set()
    video_playback = f",fps={_TILE_MOTION_ZOOMPAN_FPS}"
    for i in range(tile_count):
        skip_motion = bool(input_is_video[i]) if input_is_video is not None else False
        if motion_active and not skip_motion:
            if tile_motion == "ken-burns":
                if i not in ken_burns_animated:
                    parts.append(f"[{i}:v]{cell}[m{i}]")
                    tile_labels.append(f"m{i}")
                    continue
                zp = _zoompan_ken_burns(
                    sample_w,
                    sample_h,
                    i,
                    duration=float(duration),
                )
            else:
                zp = _zoompan_parallax(
                    sample_w,
                    sample_h,
                    i,
                    cols,
                    duration=float(duration),
                )
            # Normalize to sampled tile space while preserving aspect, then animate,
            # then downsample to final tile size.
            parts.append(f"[{i}:v]{motion_cell},{zp},{post_motion}[m{i}]")
            tile_labels.append(f"m{i}")
        else:
            playback_cell = f"{cell}{video_playback}" if skip_motion else cell
            parts.append(f"[{i}:v]{playback_cell}[s{i}]")
            tile_labels.append(f"s{i}")
    stack_inputs = "".join(f"[{label}]" for label in tile_labels)
    layout = "|".join(
        f"{(i % cols) * (cell_w + spacing)}_{(i // cols) * (cell_h + spacing)}" for i in range(tile_count)
    )
    if tile_count == 1:
        src0 = tile_labels[0]
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
