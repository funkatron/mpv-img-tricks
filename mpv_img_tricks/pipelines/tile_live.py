"""Python-native tile live slideshow runtime."""

from __future__ import annotations

import concurrent.futures
from concurrent.futures import FIRST_COMPLETED, wait
import hashlib
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from argparse import Namespace
from pathlib import Path

from mpv_img_tricks.media_discovery import discover_sources_to_playlist
from mpv_img_tricks.mpv_pipeline import run_mpv_slideshow
from mpv_img_tricks.paths import get_repo_root

_PHASE_PREFIX = "mpv-img-tricks:"
_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tiff", ".heic"}
_VIDEO_SUFFIXES = {".mov", ".mp4", ".m4v", ".mkv", ".webm", ".avi", ".mpg", ".mpeg"}

# Conservative: scale parallel ffmpeg workers down as grid/cell count grows (Pass 1).
_TILE_COMPOSITE_TILE_BUDGET = 28
_LARGE_GRID_TILE_THRESHOLD = 120
_LARGE_GRID_SAFE_RESOLUTION = (1280, 720)
_RAM_CAP_RESERVE_BYTES = 4 * 1024 * 1024 * 1024
_RAM_CAP_BYTES_PER_WORKER = int(1.25 * 1024 * 1024 * 1024)


def _probe_installed_ram_bytes() -> int | None:
    """Best-effort installed RAM in bytes. Used for Pass 3 telemetry only (not applied to caps yet)."""
    if sys.platform == "darwin":
        try:
            proc = subprocess.run(
                ["sysctl", "-n", "hw.memsize"],
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode == 0:
                raw = (proc.stdout or "").strip()
                if raw.isdigit():
                    return int(raw)
        except OSError:
            pass
    if sys.platform.startswith("linux"):
        try:
            meminfo = Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace")
            for line in meminfo.splitlines():
                if line.startswith("MemTotal:"):
                    parts = line.split()
                    if len(parts) >= 2 and parts[1].isdigit():
                        return int(parts[1]) * 1024  # kB
        except OSError:
            pass
    try:
        page_size = int(os.sysconf("SC_PAGE_SIZE"))
        phys = int(os.sysconf("SC_PHYS_PAGES"))
        return page_size * phys
    except (ValueError, OSError, AttributeError, OverflowError):
        pass
    return None


def _ram_cap_candidate_for_logging(installed_bytes: int | None) -> int | None:
    """Heuristic max concurrent workers from installed RAM."""
    if installed_bytes is None or installed_bytes <= 0:
        return None
    usable = max(installed_bytes - _RAM_CAP_RESERVE_BYTES, _RAM_CAP_BYTES_PER_WORKER)
    return max(1, int(usable // _RAM_CAP_BYTES_PER_WORKER))


def _tile_count_for_job_cap(
    *,
    cols: int,
    rows: int,
    do_randomize: bool,
    group_size: int,
    path_count: int,
) -> int:
    grid = cols * rows
    if do_randomize:
        return max(grid, min(max(group_size, 1), max(path_count, 1)))
    return max(grid, 1)


def _resolve_compositing_workers(
    *,
    cols: int,
    rows: int,
    do_randomize: bool,
    group_size: int,
    path_count: int,
    installed_ram_bytes: int | None,
    apply_ram_cap: bool,
) -> tuple[int, int, int, int | None, int | None]:
    """Returns (jobs, cpu_cap, tile_cap, ram_cap_candidate, installed_ram_bytes)."""
    tile_n = _tile_count_for_job_cap(
        cols=cols,
        rows=rows,
        do_randomize=do_randomize,
        group_size=group_size,
        path_count=path_count,
    )
    cpu_cap = max(1, (os.cpu_count() or 2) // 2)
    tile_cap = max(1, _TILE_COMPOSITE_TILE_BUDGET // tile_n)
    ram_cap = _ram_cap_candidate_for_logging(installed_ram_bytes)
    caps = [cpu_cap, tile_cap]
    if apply_ram_cap and ram_cap is not None:
        caps.append(ram_cap)
    jobs = max(1, min(caps))
    return jobs, cpu_cap, tile_cap, ram_cap, installed_ram_bytes


def _worker_limit_reason(
    *,
    jobs: int,
    cpu_cap: int,
    tile_cap: int,
    ram_cap_candidate: int | None,
    auto_ram_cap: bool,
) -> str:
    reasons: list[str] = []
    if jobs == cpu_cap:
        reasons.append("cpu")
    if jobs == tile_cap:
        reasons.append("tile")
    if auto_ram_cap and ram_cap_candidate is not None and jobs == ram_cap_candidate:
        reasons.append("ram")
    if not reasons:
        return "unknown"
    return "+".join(reasons)


def _compute_tile_layouts(
    paths: list[str],
    *,
    do_randomize: bool,
    cols: int,
    rows: int,
    group_size: int,
) -> list[tuple[int, int]]:
    """Return ordered (ccols, crows) per slide; same random choices as previous single-pass build."""
    layouts: list[tuple[int, int]] = []
    cursor = 0
    while cursor < len(paths):
        if do_randomize:
            candidates: list[tuple[int, int]] = []
            remaining = len(paths) - cursor
            for c in range(1, group_size + 1):
                for r in range(1, group_size + 1):
                    if c * r <= group_size and c * r <= remaining:
                        candidates.append((c, r))
            if not candidates:
                break
            ccols, crows = random.choice(candidates)
        else:
            ccols, crows = cols, rows
        per_slide = ccols * crows
        layouts.append((ccols, crows))
        cursor += per_slide
    return layouts


def _now_stamp() -> str:
    return time.strftime("%H:%M:%S")


def _phase(msg: str, *, quiet: bool) -> None:
    if quiet:
        return
    print(f"[{_now_stamp()}] {_PHASE_PREFIX} {msg}", file=sys.stderr)


class _Progress:
    def __init__(self, *, phase: str, label: str, total: int, quiet: bool) -> None:
        self.phase = phase
        self.label = label
        self.total = max(total, 1)
        self.quiet = quiet
        self.started = time.time()
        self.last_bucket = -1
        self.last_n = 0
        self.last_t = self.started
        self.rate_ms_per_unit = 0.0
        self.last_render_at = 0.0
        _phase(f"phase={phase} msg=start total={self.total} label={label}", quiet=quiet)

    @staticmethod
    def _fmt_duration(seconds: float) -> str:
        total = max(int(seconds), 0)
        h, rem = divmod(total, 3600)
        m, s = divmod(rem, 60)
        if h > 0:
            return f"{h:02d}:{m:02d}:{s:02d}"
        return f"{m:02d}:{s:02d}"

    def update(self, n: int, *, extra: str = "") -> None:
        if self.quiet:
            return
        n = max(0, min(n, self.total))
        now = time.time()
        elapsed = now - self.started
        delta_n = n - self.last_n
        delta_t = now - self.last_t
        if delta_n > 0 and delta_t >= 0:
            inst_rate = (delta_t * 1000.0) / float(delta_n)
            if self.rate_ms_per_unit <= 0:
                self.rate_ms_per_unit = inst_rate
            else:
                self.rate_ms_per_unit = self.rate_ms_per_unit * 0.7 + inst_rate * 0.3
            self.last_n = n
            self.last_t = now

        eta = "--:--"
        if 0 < n < self.total and self.rate_ms_per_unit > 0:
            rem = (self.total - n) * self.rate_ms_per_unit / 1000.0
            eta = self._fmt_duration(rem)

        pct = int((n * 100) / self.total)
        if sys.stderr.isatty():
            should_render = (now - self.last_render_at) >= 1.0 or n == self.total
            if not should_render:
                return
            width = 20
            filled = int((pct * width) / 100)
            bar = "=" * filled + "." * (width - filled)
            tail = f" t={self._fmt_duration(elapsed)} eta={eta}"
            if extra:
                tail += f" | {extra}"
            print(
                f"\r[{_now_stamp()}] {_PHASE_PREFIX} phase={self.phase} {self.label} [{bar}] {pct:3d}% ({n}/{self.total}){tail}",
                file=sys.stderr,
                end="",
                flush=True,
            )
            self.last_render_at = now
            return

        bucket = pct // 5
        if bucket != self.last_bucket or n == self.total:
            extra_part = f" {extra}" if extra else ""
            _phase(
                f"phase={self.phase} progress={n}/{self.total} pct={pct} elapsed={self._fmt_duration(elapsed)} eta={eta}{extra_part}",
                quiet=False,
            )
            self.last_bucket = bucket

    def finish(self, *, extra: str = "") -> None:
        if self.quiet:
            return
        if sys.stderr.isatty():
            self.update(self.total, extra=extra)
            print(file=sys.stderr)
        _phase(
            f"phase={self.phase} msg=complete total={self.total}{(' ' + extra) if extra else ''}",
            quiet=False,
        )


def _is_video(path: str) -> bool:
    return Path(path).suffix.lower() in _VIDEO_SUFFIXES


def _is_media_path(path: Path) -> bool:
    suf = path.suffix.lower()
    return suf in _IMAGE_SUFFIXES or suf in _VIDEO_SUFFIXES


def _discover_tile_sources(sources: list[str], *, order: str, recursive: bool) -> list[str]:
    # Start with image-only discovery for parity with existing ordering logic.
    paths = list(discover_sources_to_playlist(sources, order=order, recursive=recursive))
    seen = set(paths)
    for token in sources:
        expanded = os.path.expanduser(token)
        p = Path(expanded)
        if p.is_dir():
            it = p.rglob("*") if recursive else p.glob("*")
            for f in sorted(it, key=lambda x: str(x)):
                if f.is_file() and _is_media_path(f):
                    resolved = str(f.resolve())
                    if resolved not in seen:
                        seen.add(resolved)
                        paths.append(resolved)
            continue
        if p.is_file() and _is_media_path(p):
            resolved = str(p.resolve())
            if resolved not in seen:
                seen.add(resolved)
                paths.append(resolved)
            continue
        if any(c in token for c in "*?["):
            base_dir = Path(os.path.expanduser(os.path.dirname(expanded) or "."))
            glob_base = os.path.basename(expanded)
            it = base_dir.rglob(glob_base) if recursive else base_dir.glob(glob_base)
            for f in sorted(it, key=lambda x: str(x)):
                if f.is_file() and _is_media_path(f):
                    resolved = str(f.resolve())
                    if resolved not in seen:
                        seen.add(resolved)
                        paths.append(resolved)
    return paths


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


def _ffprobe_ok(path: str) -> bool:
    try:
        proc = subprocess.run(
            ["ffprobe", "-v", "error", "-threads", "1", "-i", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return True
    return proc.returncode == 0


def _validate_media(paths: list[str], *, quiet: bool) -> tuple[list[str], int]:
    if shutil.which("ffprobe") is None:
        _phase("phase=validate-media msg=ffprobe_missing skipping_probe=true", quiet=quiet)
        return paths, 0
    jobs = max((os.cpu_count() or 2) // 2, 1)
    cache_dir = Path.home() / ".cache" / "mpv-img-tricks" / "ffprobe-tile-v5"
    cache_dir.mkdir(parents=True, exist_ok=True)
    _phase(
        f"phase=validate-media msg=ffprobe_scan total_candidates={len(paths)} parallel_jobs={jobs} cache_dir={cache_dir}",
        quiet=quiet,
    )
    progress = _Progress(phase="validate-media", label="ffprobe scan", total=len(paths), quiet=quiet)

    def one(path: str) -> tuple[str, bool]:
        p = Path(path)
        try:
            key = _probe_cache_key(p)
        except OSError:
            return path, False
        cfile = cache_dir / key
        if cfile.is_file():
            return path, cfile.read_text(encoding="utf-8", errors="replace").strip() == "ok"
        ok = _ffprobe_ok(path)
        try:
            cfile.write_text("ok" if ok else "fail", encoding="utf-8")
        except OSError:
            pass
        return path, ok

    kept: list[str] = []
    skipped = 0
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        for path, ok in ex.map(one, paths):
            done += 1
            if ok:
                kept.append(path)
            else:
                skipped += 1
            progress.update(done, extra=f"kept={len(kept)} skipped={skipped}")
    progress.finish(extra=f"kept={len(kept)} skipped={skipped} checked={len(paths)}")
    return kept, skipped


def _parse_grid(grid: str | None) -> tuple[int, int]:
    raw = grid or "2x2"
    m = re.fullmatch(r"(\d+)x(\d+)", raw)
    if not m:
        raise ValueError(f"invalid --grid value: {raw!r}")
    cols, rows = int(m.group(1)), int(m.group(2))
    if cols < 1 or rows < 1:
        raise ValueError(f"invalid --grid value: {raw!r}")
    return cols, rows


def _parse_resolution(resolution: str) -> tuple[int, int]:
    m = re.fullmatch(r"(\d+)x(\d+)", resolution.strip())
    if not m:
        raise ValueError(f"invalid resolution: {resolution!r}")
    w, h = int(m.group(1)), int(m.group(2))
    if w < 1 or h < 1:
        raise ValueError(f"invalid resolution: {resolution!r}")
    return w, h


def _detect_screen_resolution(fallback: str, *, quiet: bool, prefer_fallback: bool = False) -> tuple[int, int]:
    if prefer_fallback:
        w, h = _parse_resolution(fallback)
        _phase(f"phase=screen msg=using_resolution_override size={w}x{h}", quiet=quiet)
        return w, h
    if sys.platform == "darwin" and shutil.which("system_profiler"):
        proc = subprocess.run(["system_profiler", "SPDisplaysDataType"], capture_output=True, text=True, check=False)
        for pat in (r"Resolution:\s*([0-9]+)\s*x\s*([0-9]+)", r"UI Looks like:\s*([0-9]+)\s*x\s*([0-9]+)"):
            m = re.search(pat, proc.stdout or "")
            if m:
                return int(m.group(1)), int(m.group(2))
    if shutil.which("xrandr"):
        proc = subprocess.run(["xrandr", "--current"], capture_output=True, text=True, check=False)
        m = re.search(r"([0-9]+)x([0-9]+)\s+\*", proc.stdout or "")
        if m:
            return int(m.group(1)), int(m.group(2))
    _phase(f"phase=screen msg=no_display_probe using_resolution={fallback}", quiet=quiet)
    return _parse_resolution(fallback)


def _apply_large_grid_safe_resolution(
    *,
    screen_w: int,
    screen_h: int,
    cols: int,
    rows: int,
    resolution_explicit: bool,
    safe_mode: str,
    quiet: bool,
) -> tuple[int, int]:
    tile_count = max(cols * rows, 1)
    safe_w, safe_h = _LARGE_GRID_SAFE_RESOLUTION
    if resolution_explicit or safe_mode == "off":
        return screen_w, screen_h
    if tile_count < _LARGE_GRID_TILE_THRESHOLD:
        return screen_w, screen_h
    if screen_w <= safe_w and screen_h <= safe_h:
        return screen_w, screen_h
    if safe_mode == "warn":
        _phase(
            f"phase=screen msg=large_grid_recommendation grid={cols}x{rows} "
            f"current={screen_w}x{screen_h} suggested={safe_w}x{safe_h}",
            quiet=quiet,
        )
        return screen_w, screen_h
    _phase(
        f"phase=screen msg=auto_downscale_large_grid grid={cols}x{rows} from={screen_w}x{screen_h} to={safe_w}x{safe_h}",
        quiet=quiet,
    )
    return safe_w, safe_h


def _tile_motion_is_ken_burns(args: Namespace) -> bool:
    return str(getattr(args, "tile_motion", "off")) == "ken-burns"


def _tile_slide_outputs_mp4(args: Namespace) -> bool:
    """Ken Burns needs a temporal encode; still JPEG cannot hold motion."""
    return bool(args.animate_videos) or _tile_motion_is_ken_burns(args)


def _zoompan_ken_burns(
    cell_w: int,
    cell_h: int,
    tile_index: int,
    *,
    duration: float,
    strength: float,
    parallax: str,
) -> str:
    """Return a zoompan filter chain segment (no leading label).

    Motion is driven by output frame index ``on`` (linear in time) so zoom and
    pan stay smooth. A higher output fps gives shorter steps between frames
    than 30 fps for the same wall-clock duration.
    """
    fps = 60
    d = max(2, int(max(float(duration), 1e-6) * fps))
    dm1 = max(d - 1, 1)
    strength = max(float(strength), 0.05)
    # Total zoom delta from first to last frame (was ~0.006 at strength 1 — invisible).
    z_delta = min(0.06 + 0.12 * strength, 0.28)
    if parallax == "auto":
        px = (1.0 if (tile_index % 2) == 0 else -1.0) * (0.82 + 0.04 * (tile_index % 5))
        py = (-1.0 if ((tile_index // 2) % 2) == 0 else 1.0) * (0.48 + 0.04 * ((tile_index + 1) % 5))
    else:
        px = 0.88
        py = 0.38
    px = max(-1.0, min(1.0, px))
    py = max(-1.0, min(1.0, py))
    z_expr = f"1+{z_delta:.6f}*on/{dm1}"
    x_expr = f"(iw-iw/zoom)*on/{dm1}*{px:.6f}"
    y_expr = f"(ih-ih/zoom)*on/{dm1}*{py:.6f}"
    return f"zoompan=z='{z_expr}':x='{x_expr}':y='{y_expr}':d={d}:s={cell_w}x{cell_h}:fps={fps}"


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
        f"scale={cell_w}:{cell_h}:force_original_aspect_ratio=decrease:flags={scale_flags},"
        f"pad={cell_w}:{cell_h}:(ow-iw)/2:(oh-ih)/2:black"
    )


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
    parts: list[str] = []
    motion_kb = tile_motion == "ken-burns"
    for i in range(tile_count):
        if motion_kb:
            zp = _zoompan_ken_burns(
                cell_w,
                cell_h,
                i,
                duration=float(duration),
                strength=float(tile_motion_strength),
                parallax=str(tile_parallax),
            )
            parts.append(f"[{i}:v]{cell},{zp}[m{i}]")
        else:
            parts.append(f"[{i}:v]{cell}[s{i}]")
    stack_inputs = "".join(f"[{'m' if motion_kb else 's'}{i}]" for i in range(tile_count))
    layout = "|".join(
        f"{(i % cols) * (cell_w + spacing)}_{(i // cols) * (cell_h + spacing)}" for i in range(tile_count)
    )
    if tile_count == 1:
        src0 = "m0" if motion_kb else "s0"
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


def _ffmpeg_codec_args(args: Namespace, *, out_ext: str) -> list[str]:
    tile_quality = str(getattr(args, "tile_quality", "balanced"))
    motion_mp4 = _tile_motion_is_ken_burns(args) and out_ext.lower() == ".mp4"
    if not args.animate_videos and not motion_mp4:
        if out_ext == ".png":
            return ["-frames:v", "1", "-c:v", "png"]
        quality_to_q = {"fast": "5", "balanced": "2", "high": "1"}
        # Explicit pix fmt matches filter; avoids mjpeg 'non full-range YUV' / encoder init failures.
        return ["-frames:v", "1", "-c:v", "mjpeg", "-pix_fmt", "yuvj420p", "-q:v", quality_to_q[tile_quality]]
    x264_preset = {"fast": "veryfast", "balanced": "medium", "high": "slow"}[tile_quality]
    x265_preset = {"fast": "fast", "balanced": "medium", "high": "slow"}[tile_quality]
    encoder = _animated_encoder(args)
    if encoder == "hevc_videotoolbox":
        return ["-t", str(args.duration), "-r", "30", "-an", "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-b:v", "15M", "-pix_fmt", "yuv420p"]
    if encoder == "libx265":
        return ["-t", str(args.duration), "-r", "30", "-an", "-c:v", "libx265", "-preset", x265_preset, "-crf", "25", "-pix_fmt", "yuv420p"]
    return ["-t", str(args.duration), "-r", "30", "-an", "-c:v", "libx264", "-preset", x264_preset, "-crf", "20", "-pix_fmt", "yuv420p"]


def _animated_encoder(args: Namespace) -> str:
    """Resolve animated encoder, optionally preferring VideoToolbox under hwaccel auto."""
    enc = str(getattr(args, "encoder", "auto") or "auto")
    if enc != "auto":
        return enc
    if str(getattr(args, "tile_hwaccel", "off")) == "auto" and sys.platform == "darwin":
        return "hevc_videotoolbox"
    return "libx264"


def _ffmpeg_hwaccel_args(args: Namespace) -> list[str]:
    """Experimental decode hwaccel toggle for animated tiles."""
    if not bool(getattr(args, "animate_videos", False)):
        return []
    if str(getattr(args, "tile_hwaccel", "off")) != "auto":
        return []
    return ["-hwaccel", "auto"]


def _render_slide(out_file: Path, inputs: list[str], filter_complex: str, args: Namespace) -> tuple[bool, str]:
    out_ext = out_file.suffix.lower()
    if not args.animate_videos and out_ext == ".jpg":
        filter_complex = _filter_for_still_jpeg_encode(filter_complex)
    cmd = [
        "ffmpeg",
        "-nostdin",
        "-loglevel",
        "error",
        "-threads",
        "1",
        "-filter_complex_threads",
        "1",
    ]
    cmd.extend(_ffmpeg_hwaccel_args(args))
    temporal_stills = bool(args.animate_videos) or _tile_motion_is_ken_burns(args)
    for item in inputs:
        if temporal_stills and not _is_video(item):
            cmd.extend(["-loop", "1", "-t", str(args.duration), "-i", item])
        elif _is_video(item):
            cmd.extend(["-ss", "0.25", "-i", item])
        else:
            cmd.extend(["-i", item])
    cmd.extend(["-filter_complex", filter_complex, "-map", "[out]"])
    cmd.extend(_ffmpeg_codec_args(args, out_ext=out_ext))
    cmd.append(str(out_file))
    proc = subprocess.run(cmd, check=False, capture_output=True, text=True)
    err = (proc.stderr or "").strip()
    if proc.returncode != 0 and err:
        print(err, file=sys.stderr)
    return proc.returncode == 0, err


def _composite_one_slide(
    *,
    slide_idx: int,
    ccols: int,
    crows: int,
    cursor_start: int,
    paths: list[str],
    out_dir: Path,
    ext: str,
    screen_w: int,
    screen_h: int,
    spacing: int,
    scale_mode: str,
    tile_quality: str,
    args: Namespace,
) -> bool:
    per_slide = ccols * crows
    filt, _n = _build_filter(
        cols=ccols,
        rows=crows,
        screen_w=screen_w,
        screen_h=screen_h,
        spacing=spacing,
        scale_mode=scale_mode,
        tile_quality=tile_quality,
        tile_motion=str(getattr(args, "tile_motion", "off")),
        tile_parallax=str(getattr(args, "tile_parallax", "off")),
        tile_motion_strength=float(getattr(args, "tile_motion_strength", 1.0)),
        duration=float(args.duration),
    )
    inputs = [paths[min(cursor_start + i, len(paths) - 1)] for i in range(per_slide)]
    out_file = out_dir / f"{slide_idx:04d}{ext}"
    return _render_slide(out_file, inputs, filt, args)


def _is_retryable_jpeg_failure(stderr_text: str) -> bool:
    text = stderr_text.lower()
    markers = (
        "ff_frame_thread_encoder_init failed",
        "error while opening encoder",
        "nothing was written into output file",
        "failed initializing scaling graph",
        "resource temporarily unavailable",
        "non full-range yuv is non-standard",
    )
    return any(m in text for m in markers)


def _run_mpv_filtered(cmd: list[str], *, debug: bool) -> int:
    if sys.platform != "darwin" or debug:
        return subprocess.run(cmd, check=False).returncode
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    assert proc.stderr is not None
    for line in proc.stderr:
        if "CFURLCopyResourcePropertyForKey failed because it was passed a URL which has no scheme" in line:
            continue
        if "+[IMKClient subclass]: chose IMKClient_Modern" in line:
            continue
        if "+[IMKInputSession subclass]: chose IMKInputSession_Modern" in line:
            continue
        print(line.rstrip("\n"), file=sys.stderr)
    return proc.wait()


def _master_control_token(args: Namespace) -> str:
    if bool(args.master_control):
        return "true"
    if bool(args.no_master_control):
        return "false"
    return "auto"


def _play_mpv(files: list[str], args: Namespace, *, shuffle: bool) -> int:
    repo_root = get_repo_root()
    try:
        instances = int(args.instances)
    except (TypeError, ValueError):
        print(f"Error: --instances must be a positive integer (got {args.instances!r})", file=sys.stderr)
        return 1
    if instances < 1:
        print("Error: --instances must be at least 1", file=sys.stderr)
        return 1

    with tempfile.NamedTemporaryFile(mode="w", suffix=".m3u", delete=False, encoding="utf-8") as tmp:
        for path in files:
            tmp.write(path + "\n")
        playlist = Path(tmp.name)

    passthrough = ["--hr-seek=yes", "--keep-open=no", "--media-controls=no", "--input-media-keys=no", "--force-media-title=mpv-img-tricks", "--title=mpv-img-tricks"]
    if args.sound:
        passthrough.extend([f"--audio-file={args.sound}", "--audio-display=no"])
        no_audio = False
    else:
        no_audio = True

    try:
        return run_mpv_slideshow(
            playlist,
            repo_root,
            duration=str(args.duration),
            fullscreen=True,
            shuffle=shuffle,
            loop_mode="playlist",
            scale_mode="fit",
            downscale_larger=True,
            instances=instances,
            display=args.display,
            display_map=args.display_map,
            master_control=_master_control_token(args),
            watch_ipc_socket=None,
            use_slideshow_bindings=True,
            no_audio=no_audio,
            extra_scripts=(),
            mpv_arg_passthrough=passthrough,
            debug=bool(args.debug),
        )
    finally:
        try:
            playlist.unlink()
        except OSError:
            pass


def _build_cache_key(effect: str, manifest: str, args: Namespace, screen_w: int, screen_h: int, extras: str = "") -> str:
    resolved_encoder = _animated_encoder(args) if bool(getattr(args, "animate_videos", False)) else str(getattr(args, "encoder", "auto"))
    payload = (
        f"effect={effect}\nmanifest={manifest}\nscreen={screen_w}x{screen_h}\n"
        f"duration={args.duration}\nscale={args.scale_mode}\nspacing={args.spacing or 0}\n"
        f"animate={args.animate_videos}\nencoder={args.encoder}\nresolved_encoder={resolved_encoder}\n"
        f"tile_hwaccel={getattr(args, 'tile_hwaccel', 'off')}\n"
        f"tile_quality={getattr(args, 'tile_quality', 'balanced')}\n"
        f"tile_motion={getattr(args, 'tile_motion', 'off')}\n"
        f"tile_parallax={getattr(args, 'tile_parallax', 'off')}\n"
        f"tile_motion_strength={getattr(args, 'tile_motion_strength', 1.0)}\n"
        f"{extras}\n"
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_tile_backend_command(args: Namespace) -> list[str]:
    recursive = not bool(getattr(args, "effect_no_recursive", False))
    paths = _discover_tile_sources(list(args.sources), order=args.order, recursive=recursive)
    if not paths:
        cmd = ["python-tile-live", "--no-media"]
        if getattr(args, "clear_cache", False):
            cmd.append("--clear-cache")
        return cmd
    cols, rows = _parse_grid(args.grid)
    resolution_override = bool(getattr(args, "resolution_explicit", False))
    safe_mode = str(getattr(args, "tile_safe_mode", "auto"))
    raw_w, raw_h = _detect_screen_resolution(
        args.resolution,
        quiet=True,
        prefer_fallback=resolution_override,
    )
    screen_w, screen_h = _apply_large_grid_safe_resolution(
        screen_w=raw_w,
        screen_h=raw_h,
        cols=cols,
        rows=rows,
        resolution_explicit=resolution_override,
        safe_mode=safe_mode,
        quiet=True,
    )
    if (
        len(paths) <= cols * rows
        and int(args.spacing or 0) == 0
        and str(getattr(args, "tile_motion", "off")) == "off"
    ):
        cmd = ["mpv", f"--geometry={screen_w}x{screen_h}+0+0", "--fullscreen", f"--image-display-duration={args.duration}"]
        cmd.extend(paths[: cols * rows])
        return cmd
    cmd = ["python-tile-live", f"--images={len(paths)}", f"--grid={cols}x{rows}"]
    if bool(args.randomize):
        cmd.append("--randomize")
    if getattr(args, "clear_cache", False):
        cmd.append("--clear-cache")
    return cmd


def run_tile_live(args: Namespace) -> int:
    recursive = not bool(getattr(args, "effect_no_recursive", False))
    paths = _discover_tile_sources(list(args.sources), order=args.order, recursive=recursive)
    if args.max_files and int(args.max_files) > 0:
        paths = paths[: int(args.max_files)]
    if not paths:
        print(f"Error: no images found for sources: {' '.join(args.sources)}", file=sys.stderr)
        return 1

    _phase(f"phase=discover effect=tile playlist_lines={len(paths)}", quiet=bool(args.quiet))
    _phase(f"phase=tile msg=start animate={str(bool(args.animate_videos)).lower()}", quiet=bool(args.quiet))
    paths, skipped = _validate_media(paths, quiet=bool(args.quiet))
    if skipped and not args.quiet:
        print(f"[{_now_stamp()}] Skipped {skipped} unreadable media file(s).", file=sys.stderr)
    if not paths:
        print("Error: no readable media remained for tile effect", file=sys.stderr)
        return 1

    cols, rows = _parse_grid(args.grid)
    spacing = int(args.spacing or 0)
    resolution_override = bool(getattr(args, "resolution_explicit", False))
    safe_mode = str(getattr(args, "tile_safe_mode", "auto"))
    raw_w, raw_h = _detect_screen_resolution(
        args.resolution,
        quiet=bool(args.quiet),
        prefer_fallback=resolution_override,
    )
    screen_w, screen_h = _apply_large_grid_safe_resolution(
        screen_w=raw_w,
        screen_h=raw_h,
        cols=cols,
        rows=rows,
        resolution_explicit=resolution_override,
        safe_mode=safe_mode,
        quiet=bool(args.quiet),
    )
    _phase(f"phase=screen msg=resolved size={screen_w}x{screen_h}", quiet=bool(args.quiet))
    if bool(args.animate_videos):
        hw_mode = str(getattr(args, "tile_hwaccel", "off"))
        _phase(
            f"phase=compositing-{'randomized' if bool(args.randomize) else 'fixed'} "
            f"msg=hwaccel mode={hw_mode} encoder={_animated_encoder(args)}",
            quiet=bool(args.quiet),
        )

    do_randomize = bool(args.randomize)
    tile_count = cols * rows
    if (
        len(paths) <= tile_count
        and spacing == 0
        and not do_randomize
        and int(args.instances) == 1
        and str(getattr(args, "tile_motion", "off")) == "off"
    ):
        filter_complex, n_tiles = _build_filter(
            cols=cols,
            rows=rows,
            screen_w=screen_w,
            screen_h=screen_h,
            spacing=spacing,
            scale_mode=args.scale_mode,
            tile_quality=str(getattr(args, "tile_quality", "balanced")),
        )
        cmd = ["mpv", f"--geometry={screen_w}x{screen_h}+0+0", "--fullscreen", f"--image-display-duration={args.duration}", f"--lavfi-complex={filter_complex}"]
        first = True
        for p in paths[:n_tiles]:
            if first:
                cmd.append(p)
                first = False
            else:
                cmd.append(f"--external-file={p}")
        if first:
            return 1
        return _run_mpv_filtered(cmd, debug=bool(args.debug))

    cache_root = Path.home() / ".cache" / "mpv-img-tricks" / ("tile-randomized" if do_randomize else "tile-fixed")
    cache_root.mkdir(parents=True, exist_ok=True)
    manifest = _source_manifest_hash(paths)
    extra = f"grid={cols}x{rows}\n" if not do_randomize else f"group={args.group_size or 4}\n"
    key = _build_cache_key("tile-randomized" if do_randomize else "tile-fixed", manifest, args, screen_w, screen_h, extra)
    out_dir = cache_root / key
    preferred_ext = ".mp4" if _tile_slide_outputs_mp4(args) else ".jpg"
    if not getattr(args, "clear_cache", False):
        candidate_exts = [preferred_ext]
        if not _tile_slide_outputs_mp4(args):
            candidate_exts.append(".png")
        for ext in candidate_exts:
            existing = sorted(str(p) for p in out_dir.glob(f"*{ext}"))
            if not existing:
                continue
            if ext == ".png":
                _phase(
                    f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_hit_png_fallback key={key}",
                    quiet=bool(args.quiet),
                )
            else:
                _phase(
                    f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_hit key={key}",
                    quiet=bool(args.quiet),
                )
            return _play_mpv(existing, args, shuffle=do_randomize)

    if out_dir.exists():
        shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    _phase(f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_miss key={key}", quiet=bool(args.quiet))

    group_size = max(int(args.group_size or 4), 1)
    layouts = _compute_tile_layouts(
        paths,
        do_randomize=do_randomize,
        cols=cols,
        rows=rows,
        group_size=group_size,
    )
    total_slides = len(layouts)
    if total_slides == 0:
        return 1

    installed_ram = _probe_installed_ram_bytes()
    jobs, cpu_cap, tile_cap, ram_cap_candidate, ram_bytes_for_log = _resolve_compositing_workers(
        cols=cols,
        rows=rows,
        do_randomize=do_randomize,
        group_size=group_size,
        path_count=len(paths),
        installed_ram_bytes=installed_ram,
        apply_ram_cap=bool(getattr(args, "auto_ram_cap", True)),
    )
    limit_reason = _worker_limit_reason(
        jobs=jobs,
        cpu_cap=cpu_cap,
        tile_cap=tile_cap,
        ram_cap_candidate=ram_cap_candidate,
        auto_ram_cap=bool(getattr(args, "auto_ram_cap", True)),
    )
    ram_b = "unknown" if ram_bytes_for_log is None else str(ram_bytes_for_log)
    ram_c = "unknown" if ram_cap_candidate is None else str(ram_cap_candidate)
    _phase(
        f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=job_schedule "
        f"workers={jobs} cpu_cap={cpu_cap} tile_cap={tile_cap} ram_cap_candidate={ram_c} "
        f"installed_ram_bytes={ram_b} auto_ram_cap={str(bool(getattr(args, 'auto_ram_cap', True))).lower()} "
        f"limit_reason={limit_reason} tile_budget={_TILE_COMPOSITE_TILE_BUDGET} slides={total_slides}",
        quiet=bool(args.quiet),
    )

    def run_compositing_pass(ext: str) -> tuple[int, int]:
        progress = _Progress(
            phase=f"compositing-{'randomized' if do_randomize else 'fixed'}",
            label=f"rendering {'randomized' if do_randomize else 'fixed'} composites ({ext})",
            total=total_slides,
            quiet=bool(args.quiet),
        )

        layout_idx = 0
        sched_cursor = 0

        def schedule_next(ex: concurrent.futures.ThreadPoolExecutor) -> concurrent.futures.Future[tuple[bool, str]] | None:
            nonlocal layout_idx, sched_cursor
            if layout_idx >= len(layouts):
                return None
            slide_idx = layout_idx
            ccols, crows = layouts[layout_idx]
            start = sched_cursor
            sched_cursor += ccols * crows
            layout_idx += 1
            return ex.submit(
                _composite_one_slide,
                slide_idx=slide_idx,
                ccols=ccols,
                crows=crows,
                cursor_start=start,
                paths=paths,
                out_dir=out_dir,
                ext=ext,
                screen_w=screen_w,
                screen_h=screen_h,
                spacing=spacing,
                scale_mode=args.scale_mode,
                tile_quality=str(getattr(args, "tile_quality", "balanced")),
                args=args,
            )

        done = 0
        failures = 0
        retryable = 0
        pending: set[concurrent.futures.Future[tuple[bool, str]]] = set()
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
            while len(pending) < jobs:
                fut = schedule_next(ex)
                if fut is None:
                    break
                pending.add(fut)
            while pending:
                done_now, pending = wait(pending, return_when=FIRST_COMPLETED)
                in_flight = len(pending)
                for fut in done_now:
                    ok, stderr_text = fut.result()
                    if not ok:
                        failures += 1
                        if ext == ".jpg" and _is_retryable_jpeg_failure(stderr_text):
                            retryable += 1
                    done += 1
                    approx_images = min(done * max(tile_count, 1), len(paths))
                    progress.update(done, extra=f"in_flight={in_flight} images={approx_images}/{len(paths)}")
                while len(pending) < jobs:
                    nf = schedule_next(ex)
                    if nf is None:
                        break
                    pending.add(nf)
        progress.finish(extra=f"slides={total_slides} failures={failures}")
        return failures, retryable

    output_ext = preferred_ext
    failures, retryable_failures = run_compositing_pass(output_ext)
    if failures and not _tile_slide_outputs_mp4(args) and output_ext == ".jpg" and retryable_failures > 0:
        _phase(
            f"phase=compositing-{'randomized' if do_randomize else 'fixed'} "
            f"msg=retry_png_fallback reason=jpeg_or_scaler_failure failures={failures}",
            quiet=bool(args.quiet),
        )
        for p in out_dir.glob("*.jpg"):
            try:
                p.unlink()
            except OSError:
                pass
        output_ext = ".png"
        failures, _ = run_compositing_pass(output_ext)

    files = sorted(str(p) for p in out_dir.glob(f"*{output_ext}"))
    if not files:
        return 1
    _phase(f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_saved dir={out_dir}", quiet=bool(args.quiet))
    return _play_mpv(files, args, shuffle=do_randomize)

