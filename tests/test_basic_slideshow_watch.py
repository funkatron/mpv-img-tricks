"""Watch-mode cleanup for basic live slideshow."""

from __future__ import annotations

import subprocess
import threading
import time
from pathlib import Path

import pytest

from mpv_img_tricks.pipelines import basic_slideshow as bs


def test_terminate_process_kills_running_child() -> None:
    proc = subprocess.Popen(["sleep", "30"])
    try:
        bs._terminate_process(proc)
        assert proc.poll() is not None
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=1.0)


def test_watch_loop_terminates_fswatch_when_stopped(tmp_path: Path) -> None:
    terminated = threading.Event()

    class _FakeProc:
        poll_count = 0

        def poll(self) -> int | None:
            _FakeProc.poll_count += 1
            return None

        def terminate(self) -> None:
            terminated.set()

        def wait(self, timeout: float | None = None) -> int:
            return 0

        stdout = None

    def fake_popen(*_args, **_kwargs) -> _FakeProc:
        return _FakeProc()

    stop = threading.Event()
    active: list[subprocess.Popen[bytes] | None] = [None]
    thread = threading.Thread(
        target=bs._watch_loop,
        kwargs={
            "source_dir": tmp_path,
            "recursive": True,
            "seen": set(),
            "ipc_socket": "/tmp/fake.socket",
            "stop": stop,
            "active_proc": active,
        },
        daemon=True,
    )

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(bs.subprocess, "Popen", fake_popen)
        thread.start()
        time.sleep(0.05)
        stop.set()
        bs._terminate_process(active[0])  # type: ignore[arg-type]
        thread.join(timeout=2.0)

    assert not thread.is_alive()
    assert terminated.is_set()
