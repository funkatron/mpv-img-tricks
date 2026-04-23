"""Behavior-focused checks for tile compositing worker and resolution safety policies."""

from __future__ import annotations

from argparse import Namespace

import pytest

from mpv_img_tricks.pipelines import tile_live as tl


def test_resolve_jobs_cpu_and_tile_budget_intersection(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("os.cpu_count", lambda: 8)
    jobs, cpu_cap, tile_cap, ram_cap, _ = tl._resolve_compositing_workers(
        cols=2,
        rows=2,
        do_randomize=False,
        group_size=4,
        path_count=100,
        installed_ram_bytes=16 * 1024**3,
        apply_ram_cap=False,
    )
    assert cpu_cap == 4
    assert tile_cap == tl._TILE_COMPOSITE_TILE_BUDGET // 4
    assert jobs == min(cpu_cap, tile_cap)
    assert ram_cap is not None
    assert ram_cap >= 1


def test_resolve_jobs_large_grid_throttles_to_one_worker(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("os.cpu_count", lambda: 32)
    jobs, cpu_cap, tile_cap, _, _ = tl._resolve_compositing_workers(
        cols=10,
        rows=10,
        do_randomize=False,
        group_size=4,
        path_count=100,
        installed_ram_bytes=None,
        apply_ram_cap=True,
    )
    assert cpu_cap == 16
    assert tile_cap == 1
    assert jobs == 1


def test_ram_cap_candidate_clamps_jobs_when_enabled(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("os.cpu_count", lambda: 4)
    jobs, cpu_cap, tile_cap, ram_cap, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=6 * 1024 * 1024 * 1024,
        apply_ram_cap=True,
    )
    assert cpu_cap == 2
    assert tile_cap == tl._TILE_COMPOSITE_TILE_BUDGET
    assert ram_cap == 1
    assert jobs == ram_cap


def test_ram_cap_candidate_not_applied_when_disabled(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("os.cpu_count", lambda: 4)
    jobs, cpu_cap, tile_cap, ram_cap, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=6 * 1024 * 1024 * 1024,
        apply_ram_cap=False,
    )
    assert cpu_cap == 2
    assert tile_cap == tl._TILE_COMPOSITE_TILE_BUDGET
    assert jobs == 2
    assert ram_cap == 1


def test_retryable_jpeg_failure_matches_known_encoder_and_scaler_signatures() -> None:
    stderr_blob = """
    [swscaler @ 0x123] Failed initializing scaling graph (Resource temporarily unavailable)
    [mjpeg @ 0x456] ff_frame_thread_encoder_init failed
    [out#0/image2 @ 0x789] Nothing was written into output file
    """
    assert tl._is_retryable_jpeg_failure(stderr_blob)


def test_retryable_jpeg_failure_ignores_unrelated_ffmpeg_errors() -> None:
    stderr_blob = """
    [image2 @ 0x111] Could not open file : /tmp/missing.jpg
    Error opening output files: No such file or directory
    """
    assert not tl._is_retryable_jpeg_failure(stderr_blob)


def test_detect_screen_resolution_prefers_override_value() -> None:
    w, h = tl._detect_screen_resolution("1280x720", quiet=True, prefer_fallback=True)
    assert (w, h) == (1280, 720)


def test_safe_mode_auto_downscales_large_grid_when_resolution_not_explicit() -> None:
    w, h = tl._apply_large_grid_safe_resolution(
        screen_w=3440,
        screen_h=1440,
        cols=20,
        rows=10,
        resolution_explicit=False,
        safe_mode="auto",
        quiet=True,
    )
    assert (w, h) == (1280, 720)


def test_safe_mode_warn_keeps_original_resolution() -> None:
    w, h = tl._apply_large_grid_safe_resolution(
        screen_w=3440,
        screen_h=1440,
        cols=20,
        rows=10,
        resolution_explicit=False,
        safe_mode="warn",
        quiet=True,
    )
    assert (w, h) == (3440, 1440)


def test_tile_filter_includes_quality_scale_flags() -> None:
    filt, _ = tl._build_filter(
        cols=2,
        rows=2,
        screen_w=1280,
        screen_h=720,
        spacing=0,
        scale_mode="fit",
        tile_quality="high",
    )
    assert "flags=lanczos" in filt


def test_worker_limit_reason_reports_tied_caps() -> None:
    reason = tl._worker_limit_reason(
        jobs=1,
        cpu_cap=4,
        tile_cap=1,
        ram_cap_candidate=1,
        auto_ram_cap=True,
    )
    assert reason == "tile+ram"


def test_animated_encoder_prefers_videotoolbox_on_darwin_hwaccel_auto(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tl.sys, "platform", "darwin")
    args = Namespace(encoder="auto", tile_hwaccel="auto")
    assert tl._animated_encoder(args) == "hevc_videotoolbox"


def test_animated_encoder_defaults_to_libx264_when_hwaccel_off(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tl.sys, "platform", "darwin")
    args = Namespace(encoder="auto", tile_hwaccel="off")
    assert tl._animated_encoder(args) == "libx264"


def test_ffmpeg_hwaccel_args_only_for_animated_auto_mode() -> None:
    assert tl._ffmpeg_hwaccel_args(Namespace(animate_videos=False, tile_hwaccel="auto")) == []
    assert tl._ffmpeg_hwaccel_args(Namespace(animate_videos=True, tile_hwaccel="off")) == []
    assert tl._ffmpeg_hwaccel_args(Namespace(animate_videos=True, tile_hwaccel="auto")) == ["-hwaccel", "auto"]


def test_cache_key_changes_with_tile_hwaccel_mode(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tl.sys, "platform", "darwin")
    base = dict(
        duration="1.0",
        scale_mode="fit",
        spacing="0",
        animate_videos=True,
        encoder="auto",
        tile_quality="balanced",
    )
    key_off = tl._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_hwaccel="off"),
        1280,
        720,
    )
    key_auto = tl._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_hwaccel="auto"),
        1280,
        720,
    )
    assert key_off != key_auto
