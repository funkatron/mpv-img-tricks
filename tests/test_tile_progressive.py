"""Progressive playback helpers: IPC readiness and append retries while mpv is open."""

from __future__ import annotations

import threading
import time
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

from mpv_img_tricks import mpv_ipc
from mpv_img_tricks.pipelines import tile_live as tl


def test_send_json_returns_bool_on_missing_socket(tmp_path: Path) -> None:
    assert mpv_ipc.send_json(str(tmp_path / "missing.sock"), '{"command":["get_property","pid"]}') is False


def test_play_mpv_progressive_appends_retry_until_ipc_ok(tmp_path: Path) -> None:
    """Appender must keep retrying loadfile until send_json succeeds."""
    first = tmp_path / "0000.mp4"
    first.write_bytes(b"x")
    second = tmp_path / "0001.mp4"
    second.write_bytes(b"y")

    append_q: tl.queue.Queue[str | None] = tl.queue.Queue()
    append_q.put(str(second))
    append_q.put(None)

    sends = {"n": 0}
    logged: list[str] = []

    def fake_send(_sock: str, _payload: str) -> bool:
        sends["n"] += 1
        return sends["n"] >= 3

    args = Namespace(
        duration="0.01",
        sound=None,
        display=None,
        display_map=None,
        master_control=False,
        no_master_control=False,
        debug=False,
    )

    def fake_run_mpv(*_a, **_k):  # type: ignore[no-untyped-def]
        # Give appender time to retry and succeed.
        time.sleep(0.35)
        return 0

    with (
        patch.object(mpv_ipc, "wait_until_ready", return_value=True),
        patch.object(mpv_ipc, "send_json", side_effect=fake_send),
        patch.object(mpv_ipc, "get_property", return_value="2"),
        patch.object(tl, "run_mpv_slideshow", side_effect=fake_run_mpv),
        patch.object(tl, "_phase", side_effect=lambda msg, quiet=False: logged.append(msg)),
        patch.object(tl, "get_repo_root", return_value=tmp_path),
    ):
        rc = tl._play_mpv_progressive_append(str(first), append_q, args, quiet=False)

    assert rc == 0
    assert sends["n"] >= 3
    assert any("msg=playlist_append file=0001.mp4" in m for m in logged)


def test_background_slide_work_overlaps_mpv_wait() -> None:
    """Sanity: worker threads keep making progress while a blocking wait runs."""
    hits: list[float] = []
    lock = threading.Lock()

    def worker() -> None:
        for _ in range(5):
            with lock:
                hits.append(time.monotonic())
            time.sleep(0.05)

    t = threading.Thread(target=worker, daemon=True)
    t.start()
    time.sleep(0.2)  # stand-in for mpv subprocess.run
    t.join(timeout=2.0)
    assert len(hits) >= 3
