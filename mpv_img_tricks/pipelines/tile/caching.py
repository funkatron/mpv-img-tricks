"""Cache key and media identity helpers for tile compositing."""

from __future__ import annotations

import hashlib
from argparse import Namespace
from pathlib import Path

_CACHE_COMPLETE_MARKER = "COMPLETE"


def _sha256_file_prefix(path: Path, prefix_bytes: int = 65536) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        h.update(fh.read(prefix_bytes))
    return h.hexdigest()


def _media_identity(path: Path) -> str:
    st = path.stat()
    return f"{st.st_dev}:{st.st_ino}:{st.st_size}:{int(st.st_mtime)}:{_sha256_file_prefix(path)}"


def _source_manifest_hash(paths: list[str]) -> str:
    h = hashlib.sha256()
    for p in paths:
        ident = _media_identity(Path(p))
        h.update(ident.encode("utf-8", errors="replace"))
        h.update(b"\0")
    return h.hexdigest()


def _probe_cache_key(path: Path) -> str:
    return hashlib.md5(_media_identity(path).encode("utf-8", errors="replace")).hexdigest()


def _cache_complete_path(out_dir: Path) -> Path:
    return out_dir / _CACHE_COMPLETE_MARKER


def _write_cache_complete(out_dir: Path) -> None:
    _cache_complete_path(out_dir).write_text("ok\n", encoding="utf-8")


def _cache_dir_is_complete(out_dir: Path, *, ext: str, expected_slides: int | None = None) -> bool:
    """True when COMPLETE marker exists and slide files look finished."""
    if not out_dir.is_dir():
        return False
    if not _cache_complete_path(out_dir).is_file():
        return False
    files = sorted(out_dir.glob(f"*{ext}"))
    if not files:
        return False
    if expected_slides is not None and len(files) != expected_slides:
        return False
    return True


def _build_cache_key(
    effect: str,
    manifest: str,
    args: Namespace,
    screen_w: int,
    screen_h: int,
    extras: str,
    *,
    resolved_encoder: str,
) -> str:
    payload = (
        f"effect={effect}\nmanifest={manifest}\nscreen={screen_w}x{screen_h}\n"
        f"duration={args.duration}\nscale={args.scale_mode}\nspacing={args.spacing or 0}\n"
        f"animate={args.animate_videos}\nencoder={args.encoder}\nresolved_encoder={resolved_encoder}\n"
        f"tile_hwaccel={getattr(args, 'tile_hwaccel', 'auto')}\n"
        f"tile_quality={getattr(args, 'tile_quality', 'balanced')}\n"
        f"tile_motion={getattr(args, 'tile_motion', 'off')}\n"
        f"tile_motion_defaults=vary_auto,strength_1.0,oversample_auto,parallax_short_axis_zoom_v1\n"
        f"{extras}\n"
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
