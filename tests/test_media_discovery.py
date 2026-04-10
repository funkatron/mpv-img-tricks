"""Unit tests for mpv_img_tricks.media_discovery."""

from __future__ import annotations

import tempfile
from pathlib import Path

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
