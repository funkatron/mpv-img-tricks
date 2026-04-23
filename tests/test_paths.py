"""Tests for [mpv_img_tricks.paths](mpv_img_tricks/paths.py)."""

from __future__ import annotations

from pathlib import Path

import pytest

from mpv_img_tricks.paths import get_repo_root, get_scripts_dir


def test_get_repo_root_from_package_location() -> None:
    r = get_repo_root()
    assert (r / "pyproject.toml").is_file()
    assert (r / "mpv_img_tricks" / "__init__.py").is_file()


def test_get_scripts_dir_respects_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    s = tmp_path / "scripts"
    s.mkdir()
    (s / "marker.txt").write_text("x", encoding="utf-8")
    monkeypatch.setenv("MPV_IMG_TRICKS_SCRIPTS_DIR", str(s))
    assert get_scripts_dir() == s


def test_mpv_root_invalid_raises(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    empty = tmp_path / "nope"
    empty.mkdir()
    monkeypatch.setenv("MPV_IMG_TRICKS_ROOT", str(empty))
    with pytest.raises(FileNotFoundError, match="does not look like mpv-img-tricks"):
        get_repo_root()
    monkeypatch.delenv("MPV_IMG_TRICKS_ROOT", raising=False)


def test_mpv_root_valid(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # Minimal fake checkout layout
    root = tmp_path / "repo"
    root.mkdir()
    (root / "pyproject.toml").write_text('[project]\nname = "x"\n', encoding="utf-8")
    (root / "mpv_img_tricks").mkdir()
    (root / "mpv_img_tricks" / "__init__.py").write_text("x=1\n", encoding="utf-8")
    (root / "scripts").mkdir()
    (root / "scripts" / "slideshow.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    monkeypatch.setenv("MPV_IMG_TRICKS_ROOT", str(root))
    assert get_repo_root() == root
    monkeypatch.delenv("MPV_IMG_TRICKS_ROOT", raising=False)
