"""Tile path through ``main()``: stubbed mpv/ffmpeg/ffprobe, assert phases on stderr."""

from __future__ import annotations

import sys
from contextlib import redirect_stderr
from io import StringIO
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
            "--tile-parallax",
            "auto",
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


def test_tile_live_axis_alt_uses_temporal_ffmpeg(
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
            "axis-alt",
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
