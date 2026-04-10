"""Basic live slideshow: discovery + optional watch + mpv (was ``scripts/slideshow.sh`` + ``mpv-pipeline.sh``)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

from mpv_img_tricks import mpv_ipc
from mpv_img_tricks.media_discovery import discover_sources_to_playlist
from mpv_img_tricks.mpv_pipeline import preview_mpv_commands, run_mpv_slideshow
from mpv_img_tricks.paths import get_repo_root


def master_control_token(args: object) -> str:
    if args.master_control:
        return "true"
    if args.no_master_control:
        return "false"
    return "auto"


def _require_positive_instances(args: object) -> int | None:
    try:
        n = int(args.instances)
    except (TypeError, ValueError):
        print(f"Error: --instances must be a positive integer (got {args.instances!r})", file=sys.stderr)
        return None
    if n < 1:
        print("Error: --instances must be at least 1", file=sys.stderr)
        return None
    return n


def _ipc_socket_path() -> str:
    fd, path = tempfile.mkstemp(prefix="mpv-slideshow-", suffix=".socket")
    os.close(fd)
    try:
        os.unlink(path)
    except OSError:
        pass
    return path


def _add_and_seek_to_image(ipc_socket: str, image_path: str) -> None:
    p = Path(image_path)
    if not p.is_file():
        return
    suf = p.suffix.lower()
    if suf not in (".jpg", ".jpeg", ".png", ".webp"):
        return

    raw_pos = mpv_ipc.get_property(ipc_socket, "playlist-pos").strip()
    try:
        current_pos = int(raw_pos) if raw_pos else 0
    except ValueError:
        current_pos = 0

    escaped = json.dumps(str(p.resolve()))
    mpv_ipc.send_json(ipc_socket, f'{{"command":["loadfile",{escaped},"append-play"]}}')
    time.sleep(0.2)
    target_pos = current_pos + 1
    mpv_ipc.send_json(ipc_socket, f'{{"command":["set_property","playlist-pos",{target_pos}]}}')
    print(f"➕ Added and jumped to: {p.name}")


def _watch_loop(
    source_dir: Path,
    *,
    recursive: bool,
    seen: set[str],
    ipc_socket: str,
    stop: threading.Event,
) -> None:
    include = r"\.(jpg|jpeg|png|webp)$"
    while not stop.is_set():
        cmd = [
            "fswatch",
            "-1",
            "-e",
            ".*",
            "-i",
            include,
        ]
        if recursive:
            cmd.insert(1, "-r")
        cmd.append(str(source_dir))
        try:
            out = subprocess.run(cmd, capture_output=True, check=False, timeout=None)
        except FileNotFoundError:
            return
        if stop.is_set():
            return
        if out.returncode != 0:
            time.sleep(0.3)
            continue
        line = (out.stdout.decode("utf-8", errors="replace").strip().splitlines() or [""])[-1]
        newfile = line.strip()
        if not newfile:
            continue
        time.sleep(0.2)
        try:
            resolved = str(Path(newfile).resolve())
        except OSError:
            continue
        if resolved in seen:
            continue
        if not Path(resolved).is_file():
            continue
        seen.add(resolved)
        _add_and_seek_to_image(ipc_socket, resolved)


def build_basic_live_preview_commands(args: object) -> list[list[str]]:
    """``mpv`` argv lines for ``--dry-run`` (basic live only)."""
    repo_root = get_repo_root()
    recursive = not args.no_recursive_images
    paths = discover_sources_to_playlist(
        list(args.sources),
        order=args.order,
        recursive=recursive,
    )
    if not paths:
        return []

    with tempfile.NamedTemporaryFile(mode="w", suffix=".m3u", delete=False, encoding="utf-8") as tmp:
        for line in paths:
            tmp.write(line + "\n")
        playlist = Path(tmp.name)

    try:
        n_inst = int(args.instances) if str(args.instances).isdigit() else 1
        ipc_placeholder = "/tmp/mpv-slideshow-dryrun.socket" if args.watch and n_inst == 1 else None
        return preview_mpv_commands(
            playlist,
            repo_root,
            duration=str(args.duration),
            fullscreen=True,
            shuffle=bool(args.shuffle),
            loop_mode="playlist",
            scale_mode=args.scale_mode,
            downscale_larger=True,
            instances=n_inst,
            display=args.display,
            display_map=args.display_map,
            master_control=master_control_token(args),
            watch_ipc_socket=ipc_placeholder,
            use_slideshow_bindings=True,
            no_audio=True,
            extra_scripts=(),
            mpv_arg_passthrough=(),
            debug=bool(args.debug),
        )
    finally:
        try:
            playlist.unlink()
        except OSError:
            pass


def run_basic_slideshow(args: object) -> int:
    n_inst = _require_positive_instances(args)
    if n_inst is None:
        return 1

    sm = args.scale_mode
    if sm not in ("fit", "fill", "stretch"):
        print(f"Error: invalid scale mode {sm!r}", file=sys.stderr)
        return 1

    sources = [os.path.expanduser(s) for s in args.sources]

    if args.watch:
        if n_inst != 1:
            print("Error: --watch currently requires --instances 1", file=sys.stderr)
            return 1
        if len(sources) != 1 or not Path(sources[0]).is_dir():
            print(f"Error: --watch requires a directory; got: {sources}", file=sys.stderr)
            return 1

    recursive = not args.no_recursive_images
    paths = discover_sources_to_playlist(
        list(sources),
        order=args.order,
        recursive=recursive,
    )
    if not paths:
        print(f"Error: no images found for sources: {' '.join(sources)}", file=sys.stderr)
        return 1

    ipc_socket: str | None = None
    seen_files: set[str] = set(paths)
    stop_watch = threading.Event()
    watcher: threading.Thread | None = None
    run_watch = bool(args.watch)

    if run_watch:
        if shutil.which("fswatch") is None:
            print("⚠️  Warning: fswatch not found. Install with: brew install fswatch", file=sys.stderr)
            print("   Watch mode disabled.", file=sys.stderr)
            run_watch = False
        else:
            ipc_socket = _ipc_socket_path()
            watcher = threading.Thread(
                target=_watch_loop,
                kwargs={
                    "source_dir": Path(sources[0]),
                    "recursive": not args.no_recursive,
                    "seen": seen_files,
                    "ipc_socket": ipc_socket or "",
                    "stop": stop_watch,
                },
                daemon=True,
            )
            watcher.start()

    if not getattr(args, "quiet", False):
        print("🎸 FLEXIBLE IMAGE SLIDESHOW")
        print(f"📁 Sources: {' '.join(sources)}")
        print(f"⏱️  Duration: {args.duration}s per image")
        print(f"📐 Scale mode: {sm}")
        print(f"🧩 Instances: {n_inst}")
        if args.display:
            print(f"🖥️  Display: {args.display}")
        print("")
        print(f"📸 Found {len(paths)} images")
        if run_watch:
            rec = not args.no_recursive
            print(f"👁️  Watch mode enabled (recursive: {str(rec).lower()})")
        print("🚀 Starting slideshow...")
        print("")

    repo_root = get_repo_root()

    with tempfile.NamedTemporaryFile(mode="w", suffix=".m3u", delete=False, encoding="utf-8") as tmp:
        for line in paths:
            tmp.write(line + "\n")
        playlist_path = Path(tmp.name)

    try:
        return run_mpv_slideshow(
            playlist_path,
            repo_root,
            duration=str(args.duration),
            fullscreen=True,
            shuffle=bool(args.shuffle),
            loop_mode="playlist",
            scale_mode=sm,
            downscale_larger=True,
            instances=n_inst,
            display=args.display,
            display_map=args.display_map,
            master_control=master_control_token(args),
            watch_ipc_socket=ipc_socket if run_watch else None,
            use_slideshow_bindings=True,
            no_audio=True,
            extra_scripts=(),
            mpv_arg_passthrough=(),
            debug=bool(args.debug),
        )
    finally:
        stop_watch.set()
        if watcher is not None:
            watcher.join(timeout=1.0)
        try:
            playlist_path.unlink()
        except OSError:
            pass
        if ipc_socket:
            try:
                if Path(ipc_socket).exists():
                    os.unlink(ipc_socket)
            except OSError:
                pass
