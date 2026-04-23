"""Unit tests for mpv_img_tricks.media_discovery."""

from __future__ import annotations

import os
import tempfile
import time
from pathlib import Path

import pytest

from mpv_img_tricks.media_discovery import discover_sources_to_playlist


def test_discover_natural_order_two_files() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "b.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        (d / "a.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        out = discover_sources_to_playlist([str(d)], order="natural", recursive=False)
        assert len(out) == 2
        assert Path(out[0]).name == "a.png"
        assert Path(out[1]).name == "b.png"


def test_discover_recursive_finds_subdir_images() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "sub").mkdir()
        (d / "sub" / "z.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        assert discover_sources_to_playlist([str(d)], order="natural", recursive=False) == []
        out = discover_sources_to_playlist([str(d)], order="natural", recursive=True)
        assert len(out) == 1
        assert Path(out[0]).name == "z.png"


def test_discover_includes_videos_only_when_asked() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "a.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        (d / "b.mov").write_bytes(b"not-a-real-mov")
        no_vid = discover_sources_to_playlist([str(d)], order="natural", recursive=False, include_video=False)
        assert len(no_vid) == 1
        with_vid = discover_sources_to_playlist([str(d)], order="natural", recursive=False, include_video=True)
        assert {Path(p).name for p in with_vid} == {"a.png", "b.mov"}


def test_discover_oldest_first_order_uses_mtime() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        p_old = d / "old.png"
        p_new = d / "new.png"
        p_old.write_bytes(b"\x89PNG\r\n\x1a\n")
        p_new.write_bytes(b"\x89PNG\r\n\x1a\n")
        old_t = time.time() - 100
        new_t = time.time()
        os.utime(p_old, (old_t, old_t))
        os.utime(p_new, (new_t, new_t))
        out = discover_sources_to_playlist([str(d)], order="om", recursive=False)
        assert [Path(p).name for p in out] == ["old.png", "new.png"]
        out_nm = discover_sources_to_playlist([str(d)], order="nm", recursive=False)
        assert [Path(p).name for p in out_nm] == ["new.png", "old.png"]


def test_discover_invalid_order_raises(tmp_path: Path) -> None:
    d = tmp_path / "m"
    d.mkdir()
    (d / "a.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    with pytest.raises(ValueError, match="invalid order"):
        discover_sources_to_playlist([str(d)], order="nope", recursive=False)
