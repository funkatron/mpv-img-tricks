"""CLI validation and main() routing (stubs on PATH for subprocess-backed cases)."""

from __future__ import annotations

import sys
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import pytest

from mpv_img_tricks.cli import (
    build_parser,
    build_plain_render_dry_run_line,
    main,
    validate_live_args,
)
from tests.conftest import MINIMAL_PNG


def test_validate_render_with_effect() -> None:
    p = build_parser()
    args = p.parse_args(
        [
            "live",
            "dummy",
            "--render",
            "--output",
            "o.mp4",
            "--effect",
            "tile",
        ]
    )
    with pytest.raises(SystemExit) as ex:
        validate_live_args(args, p)
    assert ex.value.code == 2


def test_validate_tile_parallax_requires_ken_burns() -> None:
    p = build_parser()
    args = p.parse_args(
        [
            "live",
            "d",
            "--effect",
            "tile",
            "--tile-parallax",
            "auto",
        ]
    )
    with pytest.raises(SystemExit) as ex:
        validate_live_args(args, p)
    assert ex.value.code == 2


def test_validate_tile_motion_strength_positive() -> None:
    p = build_parser()
    args = p.parse_args(
        [
            "live",
            "d",
            "--effect",
            "tile",
            "--tile-motion",
            "ken-burns",
            "--tile-motion-strength",
            "0",
        ]
    )
    with pytest.raises(SystemExit) as ex:
        validate_live_args(args, p)
    assert ex.value.code == 2


def test_main_help_exits(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as e:
        with patch.object(sys, "argv", ["slideshow", "-h"]):
            main()
    assert e.value.code == 0
    out = capsys.readouterr().out
    assert "playback" in out.lower() or "display" in out.lower() or "duration" in out.lower()


def test_watch_multiple_sources() -> None:
    p = build_parser()
    args = p.parse_args(
        [
            "live",
            "a",
            "b",
            "--watch",
        ]
    )
    with pytest.raises(SystemExit) as e:
        validate_live_args(args, p)
    assert e.value.code == 2


def test_dry_run_basic(capsys: pytest.CaptureFixture[str], tmp_path) -> None:
    d = tmp_path / "d"
    d.mkdir()
    (d / "x.png").write_bytes(MINIMAL_PNG)
    with patch.object(
        sys,
        "argv",
        ["slideshow", "live", str(d), "--dry-run", "--duration", "0.01", "--fill"],
    ):
        rc = main()
    assert rc == 0
    out = capsys.readouterr().out
    assert "mpv" in out


def test_effect_chaos_rejected_at_parse() -> None:
    p = build_parser()
    with pytest.raises(SystemExit):
        p.parse_args(["live", "d", "--effect", "chaos"])


def test_build_plain_render_dry_run_line() -> None:
    p = build_parser()
    args = p.parse_args(["live", "x", "--render", "--output", "a.mp4"])
    s = build_plain_render_dry_run_line(args)
    assert "plain-render" in s
    assert "ffmpeg" in s


def test_parse_fit_and_fill_rejected() -> None:
    p = build_parser()
    with pytest.raises(SystemExit) as e:
        p.parse_args(
            [
                "live",
                "d",
                "--duration",
                "0.01",
                "--fit",
                "--fill",
            ]
        )
    assert e.value.code == 2


def test_default_live_subcommand_on_path_only(
    capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    d = tmp_path / "d"
    d.mkdir()
    (d / "a.png").write_bytes(MINIMAL_PNG)
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            str(d),
            "--dry-run",
            "--duration",
            "0.01",
            "--fill",
        ],
    ):
        assert main() == 0
    out = capsys.readouterr().out
    assert "panscan=1.0" in out
    assert "--image-display-duration=0.01" in out


def test_dry_run_fit_shows_panscan_zero(
    capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    d = tmp_path / "d"
    d.mkdir()
    (d / "a.png").write_bytes(MINIMAL_PNG)
    with patch.object(
        sys,
        "argv",
        ["slideshow", "live", str(d), "--dry-run", "--duration", "0.01", "--fit"],
    ):
        assert main() == 0
    assert "panscan=0.0" in capsys.readouterr().out


def test_dry_run_tile_dry_run_includes_effect_flags(
    capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    d = tmp_path / "d"
    d.mkdir()
    (d / "a.png").write_bytes(MINIMAL_PNG)
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(d),
            "--effect",
            "tile",
            "--grid",
            "1x1",
            "--clear-cache",
            "--dry-run",
            "--duration",
            "0.01",
        ],
    ):
        assert main() == 0
    out = capsys.readouterr().out
    assert "mpv" in out
    assert "--image-display-duration=0.01" in out


def test_dry_run_plain_render_line(capsys: pytest.CaptureFixture[str], tmp_path: Path) -> None:
    d = tmp_path / "d"
    d.mkdir()
    (d / "a.png").write_bytes(MINIMAL_PNG)
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(d),
            "--render",
            "--output",
            "out.mp4",
            "--dry-run",
        ],
    ):
        assert main() == 0
    out = capsys.readouterr().out
    assert "plain-render" in out
    assert "ffmpeg" in out


def test_dry_run_two_image_sources(
    capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    (a / "1.png").write_bytes(MINIMAL_PNG)
    (b / "2.png").write_bytes(MINIMAL_PNG)
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(a),
            str(b),
            "--dry-run",
            "--duration",
            "0.01",
        ],
    ):
        assert main() == 0
    o = capsys.readouterr().out.lower()
    assert "mpv" in o
    assert "playlist" in o


def test_clear_cache_basic_emits_cache_phase(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    err = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--clear-cache",
            "--duration",
            "0.01",
        ],
    ), redirect_stderr(err):
        assert main() == 0
    assert "phase=cache" in err.getvalue()
    log = stub_bin_dir.parent / "tool.log"
    t = log.read_text(encoding="utf-8", errors="replace")
    assert "mpv" in t
    assert "playlist" in t.lower()


def test_clear_cache_plain_render_emits_cache_phase(
    two_image_dir,
    repo_root,
    stub_bin_dir,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(repo_root)
    out = tmp_path / "flip.mp4"
    err = StringIO()
    with patch.object(
        sys,
        "argv",
        [
            "slideshow",
            "live",
            str(two_image_dir),
            "--render",
            "--output",
            str(out),
            "--clear-cache",
        ],
    ), redirect_stderr(err):
        assert main() == 0
    assert "phase=cache" in err.getvalue()
    t = (stub_bin_dir.parent / "tool.log").read_text(encoding="utf-8", errors="replace")
    assert "ffmpeg" in t


def test_main_basic_multi_instance_stub_invocations(
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
            "--instances",
            "2",
            "--display-map",
            "0,1",
            "--master-control",
            "--duration",
            "0.01",
        ],
    ):
        assert main() == 0
    t = (stub_bin_dir.parent / "tool.log").read_text(encoding="utf-8", errors="replace")
    assert "--input-ipc-server=" in t
    assert "--fs-screen=0" in t
    assert "--fs-screen=1" in t

