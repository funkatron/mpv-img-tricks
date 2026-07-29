"""Worker sizing and memory helpers for tile compositing."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

# Conservative: scale parallel ffmpeg workers down as grid/cell count grows.
_TILE_COMPOSITE_TILE_BUDGET = 28
_RAM_CAP_RESERVE_BYTES = 4 * 1024 * 1024 * 1024
# Still JPEG composites: one ffmpeg tends to stay below this RSS band in practice.
_RAM_CAP_BYTES_PER_WORKER_STILL = int(1.25 * 1024 * 1024 * 1024)
# Temporal slides (Ken Burns, parallax, --animate): encode + filtergraph peak higher.
_RAM_CAP_BYTES_PER_WORKER_TEMPORAL = int(2.25 * 1024 * 1024 * 1024)
# Back-compat name for tests / external grep (still path default).
_RAM_CAP_BYTES_PER_WORKER = _RAM_CAP_BYTES_PER_WORKER_STILL
# Each temporal job runs decode + zoompan stack + encode; parallelism helps little on typical
# laptops but multiplies RSS. Keep a low hard cap separate from CPU/tile budget.
_TEMPORAL_COMPOSITE_MAX_PARALLEL = 2
# Subtracted from "available" memory before estimating how many workers fit (OS + headroom).
_RAM_CAP_AVAIL_HEADROOM_BYTES = int(1.5 * 1024 * 1024 * 1024)
# Megapixel reference (1080p) for scaling installed-RAM heuristics with output size.
_REFERENCE_OUTPUT_MP = (1920 * 1080) / 1_000_000.0


def _composite_ram_bytes_per_worker(
    *,
    temporal_composite: bool,
    screen_w: int | None = None,
    screen_h: int | None = None,
) -> int:
    """Heuristic RSS per concurrent ffmpeg for worker sizing (still vs motion/MP4)."""
    if not temporal_composite:
        return _RAM_CAP_BYTES_PER_WORKER_STILL
    base = _RAM_CAP_BYTES_PER_WORKER_TEMPORAL
    if screen_w is None or screen_h is None or screen_w <= 0 or screen_h <= 0:
        return base
    mp = (screen_w * screen_h) / 1_000_000.0
    if mp <= 0.0:
        return base
    scale = max(1.0, min(2.75, (mp / _REFERENCE_OUTPUT_MP) ** 0.7))
    return int(base * scale)


def _ram_cap_from_mem_available(
    mem_available_bytes: int | None,
    *,
    bytes_per_worker: int,
) -> int | None:
    if mem_available_bytes is None or mem_available_bytes <= 0:
        return None
    usable = mem_available_bytes - _RAM_CAP_AVAIL_HEADROOM_BYTES
    b = max(int(bytes_per_worker), 1)
    if usable < b:
        return 1
    return max(1, int(usable // b))


def _merge_ram_cap_candidates(*candidates: int | None) -> int | None:
    parts = [c for c in candidates if c is not None and c > 0]
    if not parts:
        return None
    return min(parts)


def _probe_installed_ram_bytes() -> int | None:
    """Best-effort installed RAM in bytes."""
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


def _ram_cap_candidate_for_logging(
    installed_bytes: int | None,
    *,
    bytes_per_worker: int = _RAM_CAP_BYTES_PER_WORKER_STILL,
) -> int | None:
    """Heuristic max concurrent workers from installed RAM."""
    if installed_bytes is None or installed_bytes <= 0:
        return None
    b = max(int(bytes_per_worker), 1)
    usable = max(installed_bytes - _RAM_CAP_RESERVE_BYTES, b)
    return max(1, int(usable // b))


def _linux_mem_available_bytes() -> int | None:
    try:
        txt = Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    avail: int | None = None
    for line in txt.splitlines():
        if line.startswith("MemAvailable:"):
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                avail = int(parts[1]) * 1024
    return avail


def _darwin_mem_available_bytes_estimate() -> int | None:
    """Rough free+inactive*pagesize from vm_stat (best-effort)."""
    try:
        ps = subprocess.run(
            ["sysctl", "-n", "hw.pagesize"],
            capture_output=True,
            text=True,
            check=False,
            timeout=2,
        )
        if ps.returncode != 0:
            return None
        page = int((ps.stdout or "").strip())
        vs = subprocess.run(["vm_stat"], capture_output=True, text=True, check=False, timeout=3)
        if vs.returncode != 0:
            return None
        free = inactive = 0
        for line in (vs.stdout or "").splitlines():
            ls = line.strip()
            if ls.startswith("Pages free:"):
                m = re.search(r":\s*([\d.]+)", line)
                if m:
                    free = int(float(m.group(1).replace(",", "")))
            elif ls.startswith("Pages inactive:"):
                m = re.search(r":\s*([\d.]+)", line)
                if m:
                    inactive = int(float(m.group(1).replace(",", "")))
        if free <= 0 and inactive <= 0:
            return None
        return (free + inactive) * page
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return None


def _probe_mem_available_bytes() -> int | None:
    if sys.platform == "darwin":
        return _darwin_mem_available_bytes_estimate()
    if sys.platform.startswith("linux"):
        return _linux_mem_available_bytes()
    return None


def _process_rss_bytes_self() -> int | None:
    """Current process RSS (best-effort; uses ps for portability)."""
    try:
        proc = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(os.getpid())],
            capture_output=True,
            text=True,
            check=False,
            timeout=3,
        )
        if proc.returncode != 0:
            return None
        raw = (proc.stdout or "").strip().split()
        if not raw:
            return None
        kb = int(raw[0])
        return kb * 1024
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return None


def _format_mb(n: int | None) -> str:
    if n is None or n < 0:
        return "unknown"
    return f"{n / (1024 * 1024):.0f}"


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
    temporal_composite: bool = False,
    mem_available_bytes: int | None = None,
    screen_w: int | None = None,
    screen_h: int | None = None,
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
    ram_bpw = _composite_ram_bytes_per_worker(
        temporal_composite=temporal_composite,
        screen_w=screen_w,
        screen_h=screen_h,
    )
    ram_from_installed = _ram_cap_candidate_for_logging(installed_ram_bytes, bytes_per_worker=ram_bpw)
    ram_from_avail: int | None = None
    if apply_ram_cap:
        ram_from_avail = _ram_cap_from_mem_available(mem_available_bytes, bytes_per_worker=ram_bpw)
    ram_cap = _merge_ram_cap_candidates(ram_from_installed, ram_from_avail)
    caps = [cpu_cap, tile_cap]
    if temporal_composite:
        caps.append(max(1, _TEMPORAL_COMPOSITE_MAX_PARALLEL))
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
    temporal_parallel_cap: int | None = None,
) -> str:
    reasons: list[str] = []
    if jobs == cpu_cap:
        reasons.append("cpu")
    if jobs == tile_cap:
        reasons.append("tile")
    if temporal_parallel_cap is not None and jobs == temporal_parallel_cap:
        reasons.append("temporal")
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
    max_tiles_per_slide: int | None,
    random_choice,
) -> list[tuple[int, int]]:
    """Return ordered (ccols, crows) per slide; deterministic for seeded callers."""
    layouts: list[tuple[int, int]] = []
    cursor = 0
    effective_cols = cols
    effective_rows = rows
    if not do_randomize and max_tiles_per_slide is not None and max_tiles_per_slide > 0:
        if max_tiles_per_slide < (cols * rows):
            if max_tiles_per_slide < cols:
                effective_cols = max_tiles_per_slide
                effective_rows = 1
            else:
                effective_cols = cols
                effective_rows = max(1, min(rows, max_tiles_per_slide // effective_cols))
    while cursor < len(paths):
        if do_randomize:
            candidates: list[tuple[int, int]] = []
            remaining = len(paths) - cursor
            for c in range(1, group_size + 1):
                for r in range(1, group_size + 1):
                    per_slide = c * r
                    if per_slide > group_size or per_slide > remaining:
                        continue
                    if max_tiles_per_slide is not None and max_tiles_per_slide > 0 and per_slide > max_tiles_per_slide:
                        continue
                    candidates.append((c, r))
            if not candidates:
                break
            ccols, crows = random_choice(candidates)
        else:
            ccols, crows = effective_cols, effective_rows
        per_slide = ccols * crows
        layouts.append((ccols, crows))
        cursor += per_slide
    return layouts

