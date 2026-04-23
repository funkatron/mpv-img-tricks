"""Shared pytest fixtures: repo root, minimal images, stub mpv/ffmpeg/ffprobe."""

from __future__ import annotations

import base64
import os
from collections.abc import Generator
from pathlib import Path

import pytest

# 1x1 transparent PNG
MINIMAL_PNG: bytes = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


@pytest.fixture
def repo_root() -> Path:
    """Path to the mpv-img-tricks repository root (parent of `tests/`)."""
    return Path(__file__).resolve().parent.parent


@pytest.fixture
def temp_home(tmp_path: Path) -> Path:
    """Isolated HOME for cache and config side effects."""
    h = tmp_path / "home"
    h.mkdir()
    return h


@pytest.fixture
def isolated_env(monkeypatch: pytest.MonkeyPatch, temp_home: Path) -> None:
    """Point HOME at temp dir; clear mpv-img-tricks env that could leak between tests."""
    monkeypatch.setenv("HOME", str(temp_home))
    for key in list(os.environ):
        if key.startswith("MPV_IMG_TRICKS_") and key != "MPV_IMG_TRICKS_ROOT":
            monkeypatch.delenv(key, raising=False)


def write_stub_bin(
    dest_dir: Path,
    *,
    log_path: Path | None = None,
) -> None:
    """Create stub mpv, ffmpeg, ffprobe, and optional system_profiler in ``dest_dir``."""
    dest_dir.mkdir(parents=True, exist_ok=True)

    def _wrapper(name: str, extra_body: str = "") -> None:
        log = f'"{str(log_path)}"' if log_path else '"/dev/null"'
        # Log tool basename, then args (``subprocess`` often omits argv0 from the script's ``$@``).
        body = f"""#!/usr/bin/env bash
printf '%s\\n' "$(basename "$0")" >> {log} 2>/dev/null || true
printf '%s\\n' "$@" >> {log} 2>/dev/null || true
"""
        if name == "ffmpeg":
            body += """out_file="${!#}"
if [[ -n "$out_file" && "$out_file" != -* ]]; then
  mkdir -p "$(dirname "$out_file")" 2>/dev/null || true
  touch "$out_file" 2>/dev/null || true
fi
"""
        body += f"""{extra_body}exit 0
"""
        p = dest_dir / name
        p.write_text(body, encoding="utf-8")
        p.chmod(0o755)

    _wrapper("mpv")
    _wrapper("ffprobe")
    _wrapper("ffmpeg")
    _wrapper("system_profiler", 'echo "Resolution: 1920 x 1080"\n')

    if os.name != "nt" and not (dest_dir / "xrandr").exists():
        # Linux CI: deterministic resolution if xrandr is consulted
        log_target = str(log_path) if log_path else "/dev/null"
        xr = dest_dir / "xrandr"
        xr.write_text(
            f"""#!/usr/bin/env bash
printf '%s\\n' "$(basename "$0")" >> "{log_target}" 2>/dev/null || true
printf '%s\\n' "$@" >> "{log_target}" 2>/dev/null || true
echo "  1920x1080*"
exit 0
""",
            encoding="utf-8",
        )
        xr.chmod(0o755)


@pytest.fixture
def two_image_dir(tmp_path: Path) -> Path:
    """Directory with ``a.png`` and ``b.png`` (valid minimal PNGs)."""
    d = tmp_path / "images"
    d.mkdir()
    (d / "a.png").write_bytes(MINIMAL_PNG)
    (d / "b.png").write_bytes(MINIMAL_PNG)
    return d


@pytest.fixture
def stub_bin_dir(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, isolated_env: None
) -> Generator[Path, None, None]:
    """A directory of stub tools + PATH prefix."""
    d = tmp_path / "fakebin"
    log = tmp_path / "tool.log"
    write_stub_bin(d, log_path=log)
    prefix = f"{d}{os.pathsep}{os.environ.get('PATH', '')}"
    monkeypatch.setenv("PATH", prefix)
    yield d
