"""Behavior-focused checks for tile compositing worker caps (RAM candidate is telemetry-only)."""

from __future__ import annotations

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
    )
    assert cpu_cap == 16
    assert tile_cap == 1
    assert jobs == 1


def test_ram_cap_candidate_is_not_used_to_clamp_jobs(monkeypatch: pytest.MonkeyPatch) -> None:
    """Telemetry-only: low installed RAM still yields jobs from cpu_cap/tile_cap."""
    monkeypatch.setattr("os.cpu_count", lambda: 4)
    jobs, cpu_cap, tile_cap, ram_cap, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=512 * 1024 * 1024,
    )
    assert cpu_cap == 2
    assert tile_cap == tl._TILE_COMPOSITE_TILE_BUDGET
    assert jobs == 2
    assert ram_cap == 1
    assert jobs > ram_cap


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
