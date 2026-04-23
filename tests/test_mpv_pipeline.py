"""``mpv_pipeline`` scale flags and slideshow-bindings argv (Python path, not bash)."""

from __future__ import annotations

from pathlib import Path

import pytest

from mpv_img_tricks.mpv_pipeline import build_base_args, collect_scale_flags
from mpv_img_tricks.slideshow_bindings import should_load


def test_collect_scale_flags_fit_fill_stretch() -> None:
    assert collect_scale_flags("fit", downscale_larger=True) == [
        "--keepaspect",
        "--panscan=0.0",
    ]
    assert collect_scale_flags("fill", downscale_larger=True) == [
        "--keepaspect",
        "--panscan=1.0",
    ]
    assert collect_scale_flags("stretch", downscale_larger=True) == ["--no-keepaspect"]


def test_should_load_respects_env_kill_switch(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS", raising=False)
    assert should_load(True) is True
    monkeypatch.setenv("MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS", "1")
    assert should_load(True) is False


def test_build_base_args_includes_bindings_script_when_enabled(
    repo_root: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS", raising=False)
    assert (repo_root / "mpv-scripts" / "slideshow-bindings.lua").is_file()
    base = build_base_args(
        repo_root,
        duration="1",
        fullscreen=False,
        shuffle=False,
        loop_mode="playlist",
        scale_mode="fit",
        downscale_larger=True,
        watch_ipc_socket=None,
        use_slideshow_bindings=True,
        no_audio=True,
        extra_scripts=(),
        mpv_arg_passthrough=(),
        debug=False,
    )
    assert any(x.startswith("--script=") and "slideshow-bindings.lua" in x for x in base)


def test_build_base_args_skips_bindings_when_env_unset_script(
    repo_root: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("MPV_IMG_TRICKS_NO_SLIDESHOW_BINDINGS", "yes")
    base = build_base_args(
        repo_root,
        duration="1",
        fullscreen=False,
        shuffle=False,
        loop_mode="playlist",
        scale_mode="fit",
        downscale_larger=True,
        watch_ipc_socket=None,
        use_slideshow_bindings=True,
        no_audio=True,
        extra_scripts=(),
        mpv_arg_passthrough=(),
        debug=False,
    )
    assert not any("slideshow-bindings.lua" in x for x in base)
