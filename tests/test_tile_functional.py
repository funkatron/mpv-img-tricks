"""Tile path through ``main()``: stubbed mpv/ffmpeg/ffprobe, assert phases on stderr."""

from __future__ import annotations

import os
import sys
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import pytest

from mpv_img_tricks.cli import main

pytestmark = pytest.mark.tile_functional


def test_tile_live_2x2_randomize_reaches_phases(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x2",
            "--randomize",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "phase=discover" in s
    assert "phase=validate-media" in s
    assert "phase=tile" in s

    log = stub_bin_dir.parent / "tool.log"
    out = log.read_text(encoding="utf-8", errors="replace")
    assert "mpv" in out
    assert "ffmpeg" in out


def test_tile_live_2x1_fixed_grid_lavfi_mpv(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Fixed grid (no ``--randomize``): uses mpv ``--lavfi-complex`` + xstack, not a separate ffmpeg encode."""
    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x1",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "phase=discover" in s
    assert "phase=validate-media" in s
    assert "phase=tile" in s

    log = stub_bin_dir.parent / "tool.log"
    out = log.read_text(encoding="utf-8", errors="replace")
    assert "mpv" in out
    assert "--lavfi-complex" in out


def test_tile_live_ken_burns_uses_temporal_ffmpeg(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Ken Burns forces compositing path; ffmpeg argv should include zoompan and looped still inputs."""
    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x2",
            "--randomize",
            "--tile-motion",
            "ken-burns",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    log = stub_bin_dir.parent / "tool.log"
    t = log.read_text(encoding="utf-8", errors="replace")
    assert "ffmpeg" in t
    assert "zoompan=" in t
    assert "-loop" in t


def test_tile_live_parallax_uses_temporal_ffmpeg(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x2",
            "--randomize",
            "--tile-motion",
            "parallax",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "msg=motion_sampling" in s
    log = stub_bin_dir.parent / "tool.log"
    t = log.read_text(encoding="utf-8", errors="replace")
    assert "ffmpeg" in t
    assert "zoompan=" in t


def test_tile_live_default_skips_ffprobe_validation(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x2",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "phase=validate-media msg=skipped reason=default" in s

    log = stub_bin_dir.parent / "tool.log"
    out = log.read_text(encoding="utf-8", errors="replace")
    assert "mpv" in out
    assert "ffprobe" not in out


def test_tile_live_media_validate_runs_ffprobe_phase(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x2",
            "--media-validate",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "phase=validate-media msg=ffprobe_scan" in s


def test_tile_live_parallax_single_row_writes_temporal_mp4_and_centered_motion(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--effect",
            "tile",
            "--grid",
            "2x1",
            "--tile-motion",
            "parallax",
            "--duration",
            "0.01",
        ],
    ):
        rc = main()
    assert rc == 0
    log = stub_bin_dir.parent / "tool.log"
    t = log.read_text(encoding="utf-8", errors="replace")
    assert "ffmpeg" in t
    assert "zoompan=" in t
    assert "(2*on/" in t
    cache_root = Path(os.environ["HOME"]) / ".cache" / "mpv-img-tricks" / "tile-fixed"
    assert list(cache_root.rglob("*.mp4"))


def test_tile_live_progressive_starts_after_first_slide(
    tmp_path: Path,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Multi-slide temporal runs should log progressive_start and finish remaining slides."""
    from tests.conftest import MINIMAL_PNG

    img_dir = tmp_path / "many"
    img_dir.mkdir()
    for i in range(4):
        (img_dir / f"{i}.png").write_bytes(MINIMAL_PNG)

    monkeypatch.chdir(repo_root)
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(img_dir),
            "--effect",
            "tile",
            "--grid",
            "2x1",
            "--tile-motion",
            "parallax",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "phase=playback msg=progressive_start slide=0/2 reason=ttff" in s
    cache_root = Path(os.environ["HOME"]) / ".cache" / "mpv-img-tricks" / "tile-fixed"
    assert list(cache_root.rglob("*.mp4"))
    assert list(cache_root.rglob("COMPLETE"))


def test_tile_animate_render_concats_instead_of_mpv(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """``--animate --render`` composites temporal slides then ffmpeg-concats to --output."""
    monkeypatch.chdir(repo_root)
    out = tmp_path / "animated.mp4"
    buf = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--grid",
            "2x1",
            "--animate",
            "--render",
            "--output",
            str(out),
            "--duration",
            "0.01",
            "--max-files",
            "2",
        ],
    ), redirect_stderr(buf):
        rc = main()
    assert rc == 0
    s = buf.getvalue()
    assert "phase=render msg=concat" in s
    assert out.is_file()
    log = stub_bin_dir.parent / "tool.log"
    t = log.read_text(encoding="utf-8", errors="replace")
    assert "ffmpeg" in t
    assert "\nmpv\n" not in f"\n{t}\n"


def test_tile_live_incomplete_cache_without_complete_marker_is_miss(tmp_path: Path) -> None:
    """Partial cache dirs without COMPLETE must not count as hits."""
    from mpv_img_tricks.pipelines.tile.caching import _cache_dir_is_complete

    d = tmp_path / "partial"
    d.mkdir()
    (d / "0000.mp4").write_bytes(b"x")
    assert _cache_dir_is_complete(d, ext=".mp4") is False
    (d / "COMPLETE").write_text("ok\n", encoding="utf-8")
    assert _cache_dir_is_complete(d, ext=".mp4") is True
