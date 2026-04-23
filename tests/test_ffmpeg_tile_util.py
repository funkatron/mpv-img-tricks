"""ffmpeg argv construction for tile compositing."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from mpv_img_tricks.tile.ffmpeg_util import run_composite_ffmpeg


def test_run_composite_ffmpeg_appends_stats_when_verbose(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd: list[str], **_kwargs: object) -> MagicMock:
        calls.append(cmd)
        r = MagicMock()
        r.returncode = 0
        return r

    monkeypatch.setattr("mpv_img_tricks.tile.ffmpeg_util.subprocess.run", fake_run)
    monkeypatch.setattr("mpv_img_tricks.tile.ffmpeg_util.shutil.which", lambda _s: None)
    rc = run_composite_ffmpeg(["-f", "lavfi", "-i", "color=c=black:s=1x1"], verbose_ffmpeg=True, debug=False)
    assert rc == 0
    assert len(calls) == 1
    assert "-stats" in calls[0]


def test_run_composite_ffmpeg_omits_stats_when_quiet(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd: list[str], **_kwargs: object) -> MagicMock:
        calls.append(cmd)
        r = MagicMock()
        r.returncode = 0
        return r

    monkeypatch.setattr("mpv_img_tricks.tile.ffmpeg_util.subprocess.run", fake_run)
    monkeypatch.setattr("mpv_img_tricks.tile.ffmpeg_util.shutil.which", lambda _s: None)
    run_composite_ffmpeg(["-f", "lavfi", "-i", "color=c=black:s=1x1"], verbose_ffmpeg=False, debug=False)
    assert "-stats" not in calls[0]
