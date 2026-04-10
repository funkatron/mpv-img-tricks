"""Launch mpv for slideshow-style playlists (parity with ``scripts/mpv-pipeline.sh``)."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Sequence

from mpv_img_tricks import mpv_ipc
from mpv_img_tricks.slideshow_bindings import script_path as bindings_script_path
from mpv_img_tricks.slideshow_bindings import should_load as bindings_should_load


def collect_loop_flags(loop_mode: str) -> list[str]:
    if loop_mode == "none":
        return ["--loop-file=no", "--loop-playlist=no"]
    if loop_mode == "file":
        return ["--loop-file=inf"]
    if loop_mode == "playlist":
        return ["--loop-playlist=inf"]
    msg = f"Invalid loop_mode {loop_mode!r} (expected none|file|playlist)"
    raise ValueError(msg)


def collect_scale_flags(scale_mode: str, *, downscale_larger: bool) -> list[str]:
    out: list[str]
    if scale_mode == "fit":
        out = ["--keepaspect", "--panscan=0.0"]
    elif scale_mode == "fill":
        out = ["--keepaspect", "--panscan=1.0"]
    elif scale_mode == "stretch":
        out = ["--no-keepaspect"]
    else:
        msg = f"Invalid scale_mode {scale_mode!r} (expected fit|fill|stretch)"
        raise ValueError(msg)
    if not downscale_larger:
        out.append("--no-keepaspect-window")
    return out


def collect_display_flags(*, fullscreen: bool, display_index: str) -> list[str]:
    if not display_index:
        return []
    if fullscreen:
        return [f"--fs-screen={display_index}"]
    return [f"--screen={display_index}"]


def build_base_args(
    repo_root: Path,
    *,
    duration: str,
    fullscreen: bool,
    shuffle: bool,
    loop_mode: str,
    scale_mode: str,
    downscale_larger: bool,
    watch_ipc_socket: str | None,
    use_slideshow_bindings: bool,
    no_audio: bool,
    extra_scripts: Sequence[str] | None,
    mpv_arg_passthrough: Sequence[str] | None,
    debug: bool,
) -> list[str]:
    base: list[str] = [f"--image-display-duration={duration}"]
    if fullscreen:
        base.append("--fullscreen")
    if shuffle:
        base.append("--shuffle")
    if no_audio:
        base.append("--no-audio")
    base.extend(collect_loop_flags(loop_mode))
    base.extend(collect_scale_flags(scale_mode, downscale_larger=downscale_larger))
    if watch_ipc_socket:
        base.append(f"--input-ipc-server={watch_ipc_socket}")

    if bindings_should_load(use_slideshow_bindings):
        bpath = bindings_script_path(repo_root)
        if bpath.is_file():
            base.append(f"--script={bpath}")
        elif debug:
            print(f"Debug: slideshow-bindings.lua not found at {bpath}", file=sys.stderr)

    for script_path in extra_scripts or ():
        if script_path:
            base.append(f"--script={script_path}")

    base.extend(mpv_arg_passthrough or ())
    return base


def split_playlist_round_robin(source_list: Path, instance_count: int, target_dir: Path) -> list[Path]:
    instance_playlists: list[Path] = []
    for i in range(instance_count):
        fp = target_dir / f"instance-{i + 1}.m3u"
        fp.write_text("", encoding="utf-8")
        instance_playlists.append(fp)

    index = 0
    with source_list.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            bucket = index % instance_count
            with instance_playlists[bucket].open("a", encoding="utf-8") as out:
                out.write(line + "\n")
            index += 1
    return instance_playlists


def _normalize_master_control(raw: str) -> str:
    if raw in ("yes", "true"):
        return "true"
    if raw in ("no", "false"):
        return "false"
    if raw == "auto":
        return "auto"
    msg = f"Invalid master_control {raw!r} (expected yes|no|auto)"
    raise ValueError(msg)


def _sync_followers(follower_sockets: Sequence[str], json_payload: str) -> None:
    for sock in follower_sockets:
        mpv_ipc.send_json(sock, json_payload)


def _master_control_bridge(master_socket: str, master_pid: int, follower_sockets: list[str], *, debug: bool) -> None:
    prev_pos = ""
    prev_pause = ""
    while True:
        try:
            os.kill(master_pid, 0)
        except OSError:
            break
        curr_pos = mpv_ipc.get_property(master_socket, "playlist-pos")
        curr_pause = mpv_ipc.get_property(master_socket, "pause")

        if curr_pos.lstrip("-").isdigit() and prev_pos.lstrip("-").isdigit() and curr_pos != prev_pos:
            try:
                step = int(curr_pos) - int(prev_pos)
            except ValueError:
                step = 0
            if step == 1:
                _sync_followers(follower_sockets, '{"command":["playlist-next","weak"]}')
            elif step == -1:
                _sync_followers(follower_sockets, '{"command":["playlist-prev","weak"]}')
            else:
                _sync_followers(follower_sockets, f'{{"command":["set_property","playlist-pos",{curr_pos}]}}')

        if curr_pause and curr_pause != prev_pause:
            if curr_pause == "true":
                _sync_followers(follower_sockets, '{"command":["set_property","pause",true]}')
            elif curr_pause == "false":
                _sync_followers(follower_sockets, '{"command":["set_property","pause",false]}')

        prev_pos = curr_pos
        prev_pause = curr_pause
        time.sleep(0.12)


def preview_mpv_commands(
    playlist_file: Path,
    repo_root: Path,
    *,
    duration: str,
    fullscreen: bool = True,
    shuffle: bool = False,
    loop_mode: str = "playlist",
    scale_mode: str = "fit",
    downscale_larger: bool = True,
    instances: int = 1,
    display: str | None = None,
    display_map: str | None = None,
    master_control: str = "auto",
    watch_ipc_socket: str | None = None,
    use_slideshow_bindings: bool = True,
    no_audio: bool = True,
    extra_scripts: Sequence[str] | None = None,
    mpv_arg_passthrough: Sequence[str] | None = None,
    debug: bool = False,
) -> list[list[str]]:
    """Resolved ``mpv`` argv prefixes (``["mpv", ...]``) for dry-run / logging."""
    if instances < 1:
        raise ValueError("instances must be at least 1")
    mc = _normalize_master_control(master_control)
    if instances > 1 and watch_ipc_socket:
        msg = "watch mode is currently supported only for --instances 1"
        raise ValueError(msg)
    if instances > 1 and mc == "auto":
        mc = "true"
    elif instances == 1:
        mc = "false"

    base_args = build_base_args(
        repo_root,
        duration=duration,
        fullscreen=fullscreen,
        shuffle=shuffle,
        loop_mode=loop_mode,
        scale_mode=scale_mode,
        downscale_larger=downscale_larger,
        watch_ipc_socket=watch_ipc_socket,
        use_slideshow_bindings=use_slideshow_bindings,
        no_audio=no_audio,
        extra_scripts=extra_scripts,
        mpv_arg_passthrough=mpv_arg_passthrough,
        debug=debug,
    )

    if instances == 1:
        single_args = list(base_args)
        single_args.extend(collect_display_flags(fullscreen=fullscreen, display_index=display or ""))
        single_args.append(f"--playlist={playlist_file}")
        return [["mpv", *single_args]]

    tmp_dir = tempfile.mkdtemp(prefix="mpv-dryrun-")
    try:
        instance_playlists = split_playlist_round_robin(playlist_file, instances, Path(tmp_dir))
        display_map_list = [s.strip() for s in (display_map or "").split(",") if s.strip()]
        out: list[list[str]] = []
        for i in range(instances):
            pl = instance_playlists[i]
            try:
                if not pl.exists() or pl.stat().st_size == 0:
                    continue
            except OSError:
                continue

            inst_args = list(base_args)
            if i < len(display_map_list) and display_map_list[i]:
                inst_args.extend(
                    collect_display_flags(fullscreen=fullscreen, display_index=display_map_list[i])
                )
            elif display and i == 0:
                inst_args.extend(collect_display_flags(fullscreen=fullscreen, display_index=display))

            inst_args.append(f"--input-ipc-server=/tmp/mpv-preview-{i + 1}.socket")
            inst_args.append(f"--playlist={pl}")
            out.append(["mpv", *inst_args])
        return out if out else [["mpv", *base_args, f"--playlist={playlist_file}"]]
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def run_mpv_slideshow(
    playlist_file: Path,
    repo_root: Path,
    *,
    duration: str,
    fullscreen: bool = True,
    shuffle: bool = False,
    loop_mode: str = "playlist",
    scale_mode: str = "fit",
    downscale_larger: bool = True,
    instances: int = 1,
    display: str | None = None,
    display_map: str | None = None,
    master_control: str = "auto",
    watch_ipc_socket: str | None = None,
    use_slideshow_bindings: bool = True,
    no_audio: bool = True,
    extra_scripts: Sequence[str] | None = None,
    mpv_arg_passthrough: Sequence[str] | None = None,
    debug: bool = False,
) -> int:
    """Run mpv with the same semantics as ``mpv-pipeline.sh`` (single or multi-instance)."""
    if not playlist_file.is_file():
        print(f"Error: playlist file does not exist: {playlist_file}", file=sys.stderr)
        return 1
    if instances < 1:
        print("Error: instances must be at least 1", file=sys.stderr)
        return 1

    mc = _normalize_master_control(master_control)
    if instances > 1 and watch_ipc_socket:
        print("Error: watch mode is currently supported only for --instances 1", file=sys.stderr)
        return 1

    if instances > 1 and mc == "auto":
        mc = "true"
    elif instances == 1:
        mc = "false"

    base_args = build_base_args(
        repo_root,
        duration=duration,
        fullscreen=fullscreen,
        shuffle=shuffle,
        loop_mode=loop_mode,
        scale_mode=scale_mode,
        downscale_larger=downscale_larger,
        watch_ipc_socket=watch_ipc_socket,
        use_slideshow_bindings=use_slideshow_bindings,
        no_audio=no_audio,
        extra_scripts=extra_scripts,
        mpv_arg_passthrough=mpv_arg_passthrough,
        debug=debug,
    )

    if instances == 1:
        single_args = list(base_args)
        single_args.extend(collect_display_flags(fullscreen=fullscreen, display_index=display or ""))
        single_args.append(f"--playlist={playlist_file}")
        if debug:
            print("Debug: launching single instance: mpv " + " ".join(shlex_join_safe(single_args)), file=sys.stderr)
        return subprocess.run(["mpv", *single_args], check=False).returncode

    tmp_dir = tempfile.mkdtemp(prefix="mpv-pipeline-")
    child_pids: list[int] = []
    socket_files: list[str] = []
    follower_sockets: list[str] = []
    bridge_thread: threading.Thread | None = None
    master_socket = ""
    master_pid = 0

    try:
        instance_playlists = split_playlist_round_robin(playlist_file, instances, Path(tmp_dir))
        display_map_list = [s.strip() for s in (display_map or "").split(",") if s.strip()]

        for i in range(instances):
            pl = instance_playlists[i]
            try:
                if not pl.exists() or pl.stat().st_size == 0:
                    continue
            except OSError:
                continue

            inst_args = list(base_args)
            if i < len(display_map_list) and display_map_list[i]:
                inst_args.extend(
                    collect_display_flags(fullscreen=fullscreen, display_index=display_map_list[i])
                )
            elif display and i == 0:
                inst_args.extend(collect_display_flags(fullscreen=fullscreen, display_index=display))

            fd, local_ipc = tempfile.mkstemp(prefix=f"mpv-pipeline-{i + 1}-", suffix=".socket")
            os.close(fd)
            try:
                os.unlink(local_ipc)
            except OSError:
                pass
            socket_files.append(local_ipc)
            inst_args.append(f"--input-ipc-server={local_ipc}")
            inst_args.append(f"--playlist={pl}")

            if debug:
                print(
                    f"Debug: launching instance {i + 1}: mpv " + " ".join(shlex_join_safe(inst_args)),
                    file=sys.stderr,
                )

            proc = subprocess.Popen(
                ["mpv", *inst_args],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            child_pids.append(proc.pid)

            if not master_pid:
                master_pid = proc.pid
                master_socket = local_ipc
            else:
                follower_sockets.append(local_ipc)

        if not child_pids:
            print("Error: No playable items were assigned to instances.", file=sys.stderr)
            return 1

        if mc == "true" and master_pid and follower_sockets:
            if debug:
                print(
                    f"Debug: starting master-control bridge (followers={len(follower_sockets)})",
                    file=sys.stderr,
                )

            def _bridge() -> None:
                _master_control_bridge(master_socket, master_pid, follower_sockets, debug=debug)

            bridge_thread = threading.Thread(target=_bridge, daemon=True)
            bridge_thread.start()

        while child_pids:
            pid, _ = os.waitpid(-1, 0)
            child_pids = [p for p in child_pids if p != pid]
        return 0
    finally:
        for sock in socket_files:
            try:
                os.unlink(sock)
            except OSError:
                pass
        shutil.rmtree(tmp_dir, ignore_errors=True)


def shlex_join_safe(parts: Sequence[str]) -> list[str]:
    """Quote-like display for debug (avoid importing shlex for minimal deps in hot path)."""
    out: list[str] = []
    for p in parts:
        if any(c in p for c in " \t\n\"'"):
            out.append(repr(p))
        else:
            out.append(p)
    return out
