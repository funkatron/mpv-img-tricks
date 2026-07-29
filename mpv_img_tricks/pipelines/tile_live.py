"""Python-native tile live slideshow runtime."""

from __future__ import annotations

import concurrent.futures
from concurrent.futures import FIRST_COMPLETED, wait
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
try:
    import resource
except ImportError:  # pragma: no cover - non-posix fallback
    resource = None

from mpv_img_tricks.media_discovery import discover_sources_to_playlist
from mpv_img_tricks.mpv_pipeline import run_mpv_slideshow
from mpv_img_tricks.paths import get_repo_root
from mpv_img_tricks.pipelines.tile.caching import (
    _build_cache_key,
    _probe_cache_key,
    _source_manifest_hash,
)
from mpv_img_tricks.pipelines.tile.filter_graph import (
    _build_filter,
    _filter_for_still_jpeg_encode,
    _motion_sample_scale,
    _round_even,
)
from mpv_img_tricks.pipelines.tile.motion import (
    _TILE_MOTION_TEMPORAL,
    _TILE_MOTION_ZOOMPAN_FPS,
    _tile_motion_mode,
    _tile_motion_needs_temporal_slides,
    _tile_slide_outputs_mp4,
)
from mpv_img_tricks.pipelines.tile.scheduling import (
    _TEMPORAL_COMPOSITE_MAX_PARALLEL,
    _TILE_COMPOSITE_TILE_BUDGET,
    _compute_tile_layouts,
    _composite_ram_bytes_per_worker,
    _format_mb,
    _probe_installed_ram_bytes,
    _probe_mem_available_bytes,
    _process_rss_bytes_self,
    _resolve_compositing_workers,
    _worker_limit_reason,
)

_PHASE_PREFIX = "mpv-img-tricks:"
_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tiff", ".heic"}
_VIDEO_SUFFIXES = {".mov", ".mp4", ".m4v", ".mkv", ".webm", ".avi", ".mpg", ".mpeg"}

_LARGE_GRID_TILE_THRESHOLD = 120
_LARGE_GRID_SAFE_RESOLUTION = (1280, 720)
_FFMPEG_INPUT_FD_RESERVE = 48
_FFMPEG_INPUT_HARD_CAP = 64
_FFMPEG_INPUT_CAP_ENV = "MPV_IMG_TRICKS_TILE_INPUT_CAP"


def _env_ffmpeg_input_cap() -> int | None:
    raw = os.environ.get(_FFMPEG_INPUT_CAP_ENV, "").strip()
    if not raw:
        return None
    try:
        n = int(raw)
    except ValueError:
        return None
    return n if n > 0 else None


def _ffmpeg_max_input_count() -> int:
    """Per-ffmpeg input cap (RLIMIT-aware, plus conservative decoder fan-in ceiling)."""
    cap = _env_ffmpeg_input_cap() or _FFMPEG_INPUT_HARD_CAP
    if resource is None or not hasattr(resource, "RLIMIT_NOFILE"):
        return cap
    try:
        soft_limit, _hard_limit = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (AttributeError, OSError, ValueError):
        return cap
    if soft_limit in (-1, getattr(resource, "RLIM_INFINITY", -1)) or soft_limit <= 0:
        return cap
    rlimit_cap = max(1, int(soft_limit) - _FFMPEG_INPUT_FD_RESERVE)
    return max(1, min(cap, rlimit_cap))


def _log_compositing_mem_if_due(*, done: int, total: int, in_flight: int, quiet: bool) -> None:
    """Periodic stderr snapshot: host memory hint + parent RSS (not per-ffmpeg child)."""
    if quiet or total <= 0:
        return
    step = max(1, min(10, total // 15))
    if done != total and (done % step) != 0:
        return
    avail = _probe_mem_available_bytes()
    rss = _process_rss_bytes_self()
    _phase(
        f"phase=compositing-mem msg=snapshot progress={done}/{total} in_flight={in_flight} "
        f"avail_mb={_format_mb(avail)} rss_parent_mb={_format_mb(rss)}",
        quiet=False,
    )


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


def _validate_media(paths: list[str], *, quiet: bool, skip_probe: bool = True) -> tuple[list[str], int]:
    if skip_probe:
        _phase("phase=validate-media msg=skipped reason=default", quiet=quiet)
        return paths, 0
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


def _log_motion_sampling_summary(
    *,
    layouts: list[tuple[int, int]],
    screen_w: int,
    screen_h: int,
    spacing: int,
    tile_motion_oversample: str,
    randomize: bool,
    quiet: bool,
) -> None:
    if not layouts:
        return
    samples: list[tuple[float, int, int, int, int]] = []
    for ccols, crows in layouts:
        usable_w = screen_w - spacing * (ccols - 1)
        usable_h = screen_h - spacing * (crows - 1)
        if usable_w <= 0 or usable_h <= 0:
            continue
        cell_w = usable_w // ccols
        cell_h = usable_h // crows
        scale = _motion_sample_scale(tile_motion_oversample, cell_w=cell_w, cell_h=cell_h)
        sample_w = _round_even(cell_w * scale)
        sample_h = _round_even(cell_h * scale)
        samples.append((scale, sample_w, sample_h, cell_w, cell_h))
    if not samples:
        return
    uniq = sorted(set(samples))
    mode = "randomized" if randomize else "fixed"
    setting = str(tile_motion_oversample)
    if len(uniq) == 1:
        scale, sw, sh, cw, ch = uniq[0]
        _phase(
            f"phase=compositing-{mode} msg=motion_sampling setting={setting} "
            f"resolved_scale={scale:.2f} sample={sw}x{sh} cell={cw}x{ch}",
            quiet=quiet,
        )
        return
    min_scale = min(v[0] for v in uniq)
    max_scale = max(v[0] for v in uniq)
    min_sw = min(v[1] for v in uniq)
    max_sw = max(v[1] for v in uniq)
    min_sh = min(v[2] for v in uniq)
    max_sh = max(v[2] for v in uniq)
    _phase(
        f"phase=compositing-{mode} msg=motion_sampling setting={setting} "
        f"resolved_scale_range={min_scale:.2f}-{max_scale:.2f} "
        f"sample_range={min_sw}x{min_sh}-{max_sw}x{max_sh} unique_layout_profiles={len(uniq)}",
        quiet=quiet,
    )


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


def _ffmpeg_codec_args(args: Namespace, *, out_ext: str) -> list[str]:
    tile_quality = str(getattr(args, "tile_quality", "balanced"))
    motion_mp4 = _tile_motion_needs_temporal_slides(args) and out_ext.lower() == ".mp4"
    encode_r = str(_TILE_MOTION_ZOOMPAN_FPS)
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
        return ["-t", str(args.duration), "-r", encode_r, "-an", "-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-b:v", "15M", "-pix_fmt", "yuv420p"]
    if encoder == "libx265":
        return ["-t", str(args.duration), "-r", encode_r, "-an", "-c:v", "libx265", "-preset", x265_preset, "-crf", "25", "-pix_fmt", "yuv420p"]
    return ["-t", str(args.duration), "-r", encode_r, "-an", "-c:v", "libx264", "-preset", x264_preset, "-crf", "20", "-pix_fmt", "yuv420p"]


def _animated_encoder(args: Namespace) -> str:
    """Resolve animated encoder, optionally preferring VideoToolbox under hwaccel auto."""
    enc = str(getattr(args, "encoder", "auto") or "auto")
    if enc != "auto":
        return enc
    if str(getattr(args, "tile_hwaccel", "auto")) == "auto" and sys.platform == "darwin":
        return "hevc_videotoolbox"
    return "libx264"


def _ffmpeg_hwaccel_args(args: Namespace) -> list[str]:
    """Experimental decode hwaccel toggle for animated tiles."""
    if not bool(getattr(args, "animate_videos", False)):
        return []
    if str(getattr(args, "tile_hwaccel", "auto")) != "auto":
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
    temporal_stills = bool(args.animate_videos) or _tile_motion_needs_temporal_slides(args)
    for item in inputs:
        if temporal_stills and not _is_video(item):
            cmd.extend(["-loop", "1", "-t", str(args.duration), "-i", item])
        elif _is_video(item):
            if temporal_stills:
                cmd.extend(["-ss", "0.25", "-t", str(args.duration), "-i", item])
            else:
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
    inputs = [paths[min(cursor_start + i, len(paths) - 1)] for i in range(per_slide)]
    input_is_video = [_is_video(p) for p in inputs]
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
        tile_motion_oversample=str(getattr(args, "tile_motion_oversample", "auto")),
        duration=float(args.duration),
        input_is_video=input_is_video,
    )
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
    paths, skipped = _validate_media(
        paths,
        quiet=bool(args.quiet),
        skip_probe=not bool(getattr(args, "media_validate", False)),
    )
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
        hw_mode = str(getattr(args, "tile_hwaccel", "auto"))
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
            tile_motion_oversample=str(getattr(args, "tile_motion_oversample", "auto")),
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
    key = _build_cache_key(
        "tile-randomized" if do_randomize else "tile-fixed",
        manifest,
        args,
        screen_w,
        screen_h,
        extra,
        resolved_encoder=_animated_encoder(args)
        if bool(getattr(args, "animate_videos", False))
        else str(getattr(args, "encoder", "auto")),
    )
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
                    f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_hit_png_fallback "
                    f"compositing=skipped key={key}",
                    quiet=bool(args.quiet),
                )
            else:
                _phase(
                    f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_hit "
                    f"compositing=skipped key={key}",
                    quiet=bool(args.quiet),
                )
            return _play_mpv(existing, args, shuffle=do_randomize)

    if out_dir.exists():
        shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    _phase(f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=cache_miss key={key}", quiet=bool(args.quiet))

    group_size = max(int(args.group_size or 4), 1)
    requested_tiles_per_slide = group_size if do_randomize else (cols * rows)
    max_inputs_per_slide = _ffmpeg_max_input_count()
    max_tiles_per_slide = (
        max_inputs_per_slide
        if max_inputs_per_slide is not None and max_inputs_per_slide < requested_tiles_per_slide
        else None
    )
    if max_tiles_per_slide is not None:
        _phase(
            f"phase=compositing-{'randomized' if do_randomize else 'fixed'} "
            f"msg=input_cap_applied requested_tiles_per_slide={requested_tiles_per_slide} "
            f"capped_tiles_per_slide={max_tiles_per_slide} reserve_fd={_FFMPEG_INPUT_FD_RESERVE} "
            f"hard_cap={_FFMPEG_INPUT_HARD_CAP} env_cap={os.environ.get(_FFMPEG_INPUT_CAP_ENV, '') or 'unset'}",
            quiet=bool(args.quiet),
        )
    layouts = _compute_tile_layouts(
        paths,
        do_randomize=do_randomize,
        cols=cols,
        rows=rows,
        group_size=group_size,
        max_tiles_per_slide=max_tiles_per_slide,
        random_choice=random.choice,
    )
    total_slides = len(layouts)
    if total_slides == 0:
        return 1
    if str(getattr(args, "tile_motion", "off")) != "off":
        _log_motion_sampling_summary(
            layouts=layouts,
            screen_w=screen_w,
            screen_h=screen_h,
            spacing=spacing,
            tile_motion_oversample=str(getattr(args, "tile_motion_oversample", "auto")),
            randomize=do_randomize,
            quiet=bool(args.quiet),
        )

    installed_ram = _probe_installed_ram_bytes()
    temporal_slide = _tile_slide_outputs_mp4(args)
    mem_avail = _probe_mem_available_bytes()
    ram_bpw = _composite_ram_bytes_per_worker(
        temporal_composite=temporal_slide,
        screen_w=screen_w,
        screen_h=screen_h,
    )
    jobs, cpu_cap, tile_cap, ram_cap_candidate, ram_bytes_for_log = _resolve_compositing_workers(
        cols=cols,
        rows=rows,
        do_randomize=do_randomize,
        group_size=group_size,
        path_count=len(paths),
        installed_ram_bytes=installed_ram,
        apply_ram_cap=bool(getattr(args, "auto_ram_cap", True)),
        temporal_composite=temporal_slide,
        mem_available_bytes=mem_avail if bool(getattr(args, "auto_ram_cap", True)) else None,
        screen_w=screen_w,
        screen_h=screen_h,
    )
    limit_reason = _worker_limit_reason(
        jobs=jobs,
        cpu_cap=cpu_cap,
        tile_cap=tile_cap,
        ram_cap_candidate=ram_cap_candidate,
        auto_ram_cap=bool(getattr(args, "auto_ram_cap", True)),
        temporal_parallel_cap=_TEMPORAL_COMPOSITE_MAX_PARALLEL if temporal_slide else None,
    )
    ram_b = "unknown" if ram_bytes_for_log is None else str(ram_bytes_for_log)
    ram_c = "unknown" if ram_cap_candidate is None else str(ram_cap_candidate)
    _phase(
        f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=job_schedule "
        f"workers={jobs} cpu_cap={cpu_cap} tile_cap={tile_cap} ram_cap_candidate={ram_c} "
        f"installed_ram_bytes={ram_b} auto_ram_cap={str(bool(getattr(args, 'auto_ram_cap', True))).lower()} "
        f"limit_reason={limit_reason} tile_budget={_TILE_COMPOSITE_TILE_BUDGET} slides={total_slides} "
        f"temporal_composite={str(temporal_slide).lower()} temporal_max_parallel="
        f"{_TEMPORAL_COMPOSITE_MAX_PARALLEL if temporal_slide else 0} ram_bytes_per_worker={ram_bpw}",
        quiet=bool(args.quiet),
    )
    if not args.quiet:
        avail = _probe_mem_available_bytes()
        rss = _process_rss_bytes_self()
        _phase(
            f"phase=compositing-{'randomized' if do_randomize else 'fixed'} msg=mem_baseline "
            f"avail_mb={_format_mb(avail)} rss_parent_mb={_format_mb(rss)}",
            quiet=False,
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
                _log_compositing_mem_if_due(
                    done=done,
                    total=total_slides,
                    in_flight=len(pending),
                    quiet=bool(args.quiet),
                )
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

