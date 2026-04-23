"""Optional JSON config → ``live`` subparser defaults."""

from __future__ import annotations

from pathlib import Path

import pytest

from mpv_img_tricks.config import live_subparser_defaults, load_config
from mpv_img_tricks.cli import build_parser


def test_load_config_and_subparser_mapping(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    p = tmp_path / "c.json"
    p.write_text('{"duration": 3.0, "scale_mode": "fill", "quiet": true}', encoding="utf-8")
    monkeypatch.setenv("MPV_IMG_TRICKS_CONFIG", str(p))
    cfg = load_config()
    d = live_subparser_defaults(cfg)
    assert d["duration"] == "3.0"
    assert d["scale_mode"] == "fill"
    assert d["quiet"] is True


def test_build_parser_uses_config_file_defaults(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    p = tmp_path / "x.json"
    p.write_text('{"duration": 9.5, "img_per_sec": 30}', encoding="utf-8")
    monkeypatch.setenv("MPV_IMG_TRICKS_CONFIG", str(p))
    a = build_parser().parse_args(["live", "dummy"])
    assert a.duration == "9.5"
    assert a.img_per_sec == "30"
