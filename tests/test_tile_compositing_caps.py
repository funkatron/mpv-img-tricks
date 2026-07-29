"""Behavior-focused checks for tile compositing worker and resolution safety policies."""

from __future__ import annotations

from argparse import Namespace

import pytest

from mpv_img_tricks.pipelines import tile_live as tl
from mpv_img_tricks.pipelines.tile import caching as tc
from mpv_img_tricks.pipelines.tile.scheduling import _TEMPORAL_COMPOSITE_MAX_PARALLEL


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


def test_temporal_parallel_cap_limits_workers(monkeypatch: pytest.MonkeyPatch) -> None:
    """Motion/MP4 path caps ffmpeg fan-out independent of CPU when RAM is ample."""
    monkeypatch.setattr("os.cpu_count", lambda: 16)
    jobs, cpu_cap, tile_cap, _, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=128 * 1024**3,
        apply_ram_cap=True,
        temporal_composite=True,
    )
    assert cpu_cap == 8
    assert tile_cap == tl._TILE_COMPOSITE_TILE_BUDGET
    assert jobs == _TEMPORAL_COMPOSITE_MAX_PARALLEL


def test_low_mem_available_clamps_workers_below_temporal_cap(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("os.cpu_count", lambda: 16)
    jobs, _, _, _, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=32 * 1024**3,
        apply_ram_cap=True,
        temporal_composite=True,
        mem_available_bytes=2 * 1024**3,
        screen_w=3440,
        screen_h=1440,
    )
    assert jobs == 1


def test_compute_tile_layouts_caps_fixed_grid_by_max_tiles_per_slide() -> None:
    paths = [f"/tmp/{i}.jpg" for i in range(751)]
    layouts = tl._compute_tile_layouts(
        paths,
        do_randomize=False,
        cols=20,
        rows=20,
        group_size=4,
        max_tiles_per_slide=208,
        random_choice=lambda items: items[0],
    )
    assert layouts
    assert all((c * r) <= 208 for c, r in layouts)
    assert all((c, r) == (20, 10) for c, r in layouts)
    assert len(layouts) == 4


def test_compute_tile_layouts_caps_randomized_candidates_by_max_tiles_per_slide() -> None:
    paths = [f"/tmp/{i}.jpg" for i in range(64)]
    layouts = tl._compute_tile_layouts(
        paths,
        do_randomize=True,
        cols=8,
        rows=8,
        group_size=16,
        max_tiles_per_slide=6,
        random_choice=lambda items: max(items, key=lambda pair: pair[0] * pair[1]),
    )
    assert layouts
    assert all((c * r) <= 6 for c, r in layouts)


def test_ffmpeg_max_input_count_uses_hard_cap_when_resource_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tl, "resource", None)
    assert tl._ffmpeg_max_input_count() == tl._FFMPEG_INPUT_HARD_CAP


def test_ffmpeg_max_input_count_is_min_of_hard_and_rlimit(monkeypatch: pytest.MonkeyPatch) -> None:
    class _FakeResource:
        RLIMIT_NOFILE = 7
        RLIM_INFINITY = 10**12

        @staticmethod
        def getrlimit(_kind: int) -> tuple[int, int]:
            return (256, 256)

    monkeypatch.setattr(tl, "resource", _FakeResource)
    assert tl._ffmpeg_max_input_count() == tl._FFMPEG_INPUT_HARD_CAP


def test_ffmpeg_max_input_count_honors_tight_rlimit(monkeypatch: pytest.MonkeyPatch) -> None:
    class _FakeResource:
        RLIMIT_NOFILE = 7
        RLIM_INFINITY = 10**12

        @staticmethod
        def getrlimit(_kind: int) -> tuple[int, int]:
            return (72, 256)

    monkeypatch.setattr(tl, "resource", _FakeResource)
    assert tl._ffmpeg_max_input_count() == 24


def test_env_ffmpeg_input_cap_uses_positive_int(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MPV_IMG_TRICKS_TILE_INPUT_CAP", "96")
    assert tl._env_ffmpeg_input_cap() == 96


def test_env_ffmpeg_input_cap_ignores_invalid_values(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MPV_IMG_TRICKS_TILE_INPUT_CAP", "abc")
    assert tl._env_ffmpeg_input_cap() is None
    monkeypatch.setenv("MPV_IMG_TRICKS_TILE_INPUT_CAP", "0")
    assert tl._env_ffmpeg_input_cap() is None


def test_ffmpeg_max_input_count_prefers_env_cap_over_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MPV_IMG_TRICKS_TILE_INPUT_CAP", "64")
    monkeypatch.setattr(tl, "resource", None)
    assert tl._ffmpeg_max_input_count() == 64


def test_worker_limit_reason_reports_temporal_cap() -> None:
    reason = tl._worker_limit_reason(
        jobs=2,
        cpu_cap=8,
        tile_cap=28,
        ram_cap_candidate=7,
        auto_ram_cap=True,
        temporal_parallel_cap=2,
    )
    assert reason == "temporal"


def test_temporal_composite_uses_stricter_ram_per_worker(monkeypatch: pytest.MonkeyPatch) -> None:
    """MP4 / motion paths assume higher per-ffmpeg RSS → smaller ram_cap than still JPEG."""
    monkeypatch.setattr("os.cpu_count", lambda: 32)
    ten_gb = 10 * 1024 * 1024 * 1024
    jobs_still, _, _, ram_still, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=ten_gb,
        apply_ram_cap=True,
        temporal_composite=False,
    )
    jobs_temp, _, _, ram_temp, _ = tl._resolve_compositing_workers(
        cols=1,
        rows=1,
        do_randomize=False,
        group_size=4,
        path_count=10,
        installed_ram_bytes=ten_gb,
        apply_ram_cap=True,
        temporal_composite=True,
    )
    assert ram_still is not None and ram_temp is not None
    assert ram_still > ram_temp
    assert jobs_temp <= jobs_still


def test_mem_probe_helpers_do_not_raise() -> None:
    tl._probe_mem_available_bytes()
    tl._process_rss_bytes_self()
    assert tl._format_mb(1024 * 1024) == "1"


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
    assert "force_divisible_by=2" in filt


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


def test_ffmpeg_codec_still_motion_mp4_matches_zoompan_fps() -> None:
    """Ken Burns / parallax MP4 must not use -r 30 while zoompan emits higher fps (was visibly choppy)."""
    args = Namespace(
        animate_videos=False,
        duration="2.0",
        encoder="auto",
        tile_hwaccel="off",
        tile_quality="balanced",
        tile_motion="ken-burns",
    )
    cmd = tl._ffmpeg_codec_args(args, out_ext=".mp4")
    assert cmd[cmd.index("-r") + 1] == str(tl._TILE_MOTION_ZOOMPAN_FPS)


def test_ffmpeg_codec_animate_videos_mp4_uses_60fps() -> None:
    args = Namespace(
        animate_videos=True,
        duration="2.0",
        encoder="auto",
        tile_hwaccel="off",
        tile_quality="balanced",
        tile_motion="off",
    )
    cmd = tl._ffmpeg_codec_args(args, out_ext=".mp4")
    assert cmd[cmd.index("-r") + 1] == str(tl._TILE_MOTION_ZOOMPAN_FPS)


def test_ffmpeg_codec_animate_with_parallax_matches_zoompan_fps() -> None:
    """--animate still pans must encode at zoompan fps even when animate_videos is on."""
    args = Namespace(
        animate_videos=True,
        duration="2.0",
        encoder="auto",
        tile_hwaccel="off",
        tile_quality="balanced",
        tile_motion="parallax",
    )
    cmd = tl._ffmpeg_codec_args(args, out_ext=".mp4")
    assert cmd[cmd.index("-r") + 1] == str(tl._TILE_MOTION_ZOOMPAN_FPS)


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
    key_off = tc._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_hwaccel="off"),
        1280,
        720,
        "",
        resolved_encoder="libx264",
    )
    key_auto = tc._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_hwaccel="auto"),
        1280,
        720,
        "",
        resolved_encoder="hevc_videotoolbox",
    )
    assert key_off != key_auto


def test_cache_key_changes_with_tile_motion_settings() -> None:
    base = dict(
        duration="1.0",
        scale_mode="fit",
        spacing="0",
        animate_videos=False,
        encoder="auto",
        tile_quality="balanced",
        tile_hwaccel="off",
    )
    key_off = tc._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_motion="off"),
        1280,
        720,
        "",
        resolved_encoder="auto",
    )
    key_kb = tc._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_motion="ken-burns"),
        1280,
        720,
        "",
        resolved_encoder="auto",
    )
    key_par = tc._build_cache_key(
        "tile-fixed",
        "manifest-x",
        Namespace(**base, tile_motion="parallax"),
        1280,
        720,
        "",
        resolved_encoder="auto",
    )
    assert key_off != key_kb
    assert key_kb != key_par


def test_build_filter_ken_burns_includes_zoompan() -> None:
    filt, n = tl._build_filter(
        cols=2,
        rows=1,
        screen_w=640,
        screen_h=360,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="ken-burns",
        duration=1.0,
    )
    assert n == 2
    assert "zoompan=" in filt
    assert "[m0]" in filt and "[m1]" in filt
    assert "xstack=inputs=2" in filt


def test_build_filter_ken_burns_animates_all_tiles_for_modest_grids() -> None:
    """Grids up to 16 tiles animate every Ken Burns input; larger grids subsample."""
    filt8, _ = tl._build_filter(
        cols=8,
        rows=1,
        screen_w=1600,
        screen_h=200,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="ken-burns",
        duration=1.0,
    )
    assert filt8.count("zoompan=") == 8
    filt1, _ = tl._build_filter(
        cols=1,
        rows=1,
        screen_w=320,
        screen_h=200,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="ken-burns",
        duration=1.0,
    )
    assert filt1.count("zoompan=") == 1
    filt20, _ = tl._build_filter(
        cols=20,
        rows=1,
        screen_w=4000,
        screen_h=200,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="ken-burns",
        duration=1.0,
    )
    assert filt20.count("zoompan=") == max(1, 20 // 4)


def test_build_filter_ken_burns_four_wide_animates_each_tile() -> None:
    filt, n = tl._build_filter(
        cols=4,
        rows=1,
        screen_w=1280,
        screen_h=360,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="ken-burns",
        duration=2.0,
    )
    assert n == 4
    assert filt.count("zoompan=") == 4


def test_build_filter_ken_burns_varies_zoompan_between_tiles() -> None:
    filt, _ = tl._build_filter(
        cols=2,
        rows=1,
        screen_w=640,
        screen_h=360,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="ken-burns",
        duration=2.0,
    )
    assert "(2*on/" in filt
    assert f"fps={tl._TILE_MOTION_ZOOMPAN_FPS}" in filt
    segs = [s for s in filt.split(";") if "zoompan=" in s]
    assert len(segs) == 2

    def _zoompan_expr(seg: str) -> str:
        z = seg.split("zoompan=", 1)[1]
        return z.split(",scale=", 1)[0]

    assert _zoompan_expr(segs[0]) != _zoompan_expr(segs[1])


def test_build_filter_parallax_row_swapped_xy_assignment() -> None:
    import re

    filt, _ = tl._build_filter(
        cols=2,
        rows=2,
        screen_w=640,
        screen_h=360,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="parallax",
        duration=2.0,
    )
    z0 = next(s for s in filt.split(";") if s.startswith("[0:v]"))
    z1 = next(s for s in filt.split(";") if s.startswith("[1:v]"))
    z2 = next(s for s in filt.split(";") if s.startswith("[2:v]"))
    z3 = next(s for s in filt.split(";") if s.startswith("[3:v]"))

    def axes(seg: str) -> tuple[float, float]:
        mx = float(re.search(r"x='[^']*0\.5\*([0-9.-]+)\*", seg).group(1))
        my = float(re.search(r"y='[^']*0\.5\*([0-9.-]+)\*", seg).group(1))
        return mx, my

    mx0, my0 = axes(z0)
    mx1, my1 = axes(z1)
    mx2, my2 = axes(z2)
    mx3, my3 = axes(z3)
    # Row 0: Y, X — Row 1: X, Y
    assert abs(mx0) < 1e-9 and abs(my0) > 0.2
    assert abs(mx1) > 0.2 and abs(my1) < 1e-9
    assert abs(mx2) > 0.2 and abs(my2) < 1e-9
    assert abs(mx3) < 1e-9 and abs(my3) > 0.2
    z0z = re.search(r"zoompan=z='([^']+)'", z0).group(1)
    assert "on" not in z0z


def test_parallax_narrow_cell_raises_zoom_on_horizontal_pan() -> None:
    """Tall narrow cells (e.g. 30x2) need higher zoom on X pans or travel is only a few px."""
    import re

    filt, _ = tl._build_filter(
        cols=8,
        rows=1,
        screen_w=400,
        screen_h=800,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="parallax",
        duration=2.0,
    )
    # cell ~50x800; row0 is Y,X,… — tile 0 pans Y (long), tile 1 pans X (short)
    z0 = next(s for s in filt.split(";") if s.startswith("[0:v]"))
    z1 = next(s for s in filt.split(";") if s.startswith("[1:v]"))
    zoom_y = float(re.search(r"zoompan=z='([0-9.]+)'", z0).group(1))
    zoom_x = float(re.search(r"zoompan=z='([0-9.]+)'", z1).group(1))
    assert zoom_x > zoom_y + 1.0
    assert zoom_x <= 4.0 + 1e-6


def test_build_filter_skips_motion_on_video_inputs() -> None:
    filt, _ = tl._build_filter(
        cols=2,
        rows=1,
        screen_w=640,
        screen_h=360,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="parallax",
        duration=2.0,
        input_is_video=[True, False],
    )
    v0 = next(s for s in filt.split(";") if s.startswith("[0:v]"))
    v1 = next(s for s in filt.split(";") if s.startswith("[1:v]"))
    assert "zoompan=" not in v0
    assert f"fps={tl._TILE_MOTION_ZOOMPAN_FPS}" in v0
    assert "zoompan=" in v1


def test_build_filter_motion_oversample_auto_scales_small_tiles() -> None:
    filt, _ = tl._build_filter(
        cols=6,
        rows=1,
        screen_w=600,
        screen_h=120,
        spacing=0,
        scale_mode="fit",
        tile_quality="balanced",
        tile_motion="parallax",
        duration=2.0,
    )
    # cell is 100x120; auto oversample for small tiles emits zoompan at 200x240.
    assert "s=200x240" in filt
    assert "force_original_aspect_ratio=decrease" in filt


def test_build_filter_motion_preserves_aspect_before_zoompan() -> None:
    filt, _ = tl._build_filter(
        cols=6,
        rows=6,
        screen_w=1920,
        screen_h=1080,
        spacing=0,
        scale_mode="fit",
        tile_quality="high",
        tile_motion="parallax",
        duration=2.0,
    )
    # Aspect normalization should occur before zoompan for motion paths.
    assert "force_original_aspect_ratio=decrease" in filt
    assert "zoompan=" in filt
