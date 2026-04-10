"""Plain image directory → flipbook video (parity with scripts/images-to-video.sh core path)."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from argparse import Namespace
from pathlib import Path

from mpv_img_tricks.media_discovery import discover_sources_to_playlist


def run_plain_render(args: Namespace) -> int:
    """Build concat demuxer list and run ffmpeg (VideoToolbox on macOS, libx264 elsewhere)."""
    paths = discover_sources_to_playlist(
        list(args.sources),
        order="natural",
        recursive=True,
    )
    if not paths:
        print(f"Error: No images found for sources: {' '.join(args.sources)}", flush=True)
        return 1

    output = Path(args.output or "flipbook.mp4").expanduser()
    resolution = args.resolution
    img_per_sec = str(args.img_per_sec)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False, encoding="utf-8", errors="surrogateescape") as cf:
        concat_path = cf.name
        for f in paths:
            # concat demuxer safe quoting
            esc = f.replace("'", "'\\''")
            cf.write(f"file '{esc}'\n")

    if sys.platform == "darwin":
        vcodec = [
            "-c:v",
            "hevc_videotoolbox",
            "-tag:v",
            "hvc1",
            "-b:v",
            "25M",
            "-maxrate",
            "55M",
            "-bufsize",
            "100M",
        ]
    else:
        vcodec = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "fast", "-crf", "23"]

    cmd = [
        "ffmpeg",
        "-nostdin",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        concat_path,
        "-r",
        img_per_sec,
        "-vf",
        f"scale={resolution}:flags=lanczos,fps={img_per_sec}",
        *vcodec,
        "-an",
        "-y",
        str(output),
    ]

    try:
        proc = subprocess.run(
            cmd,
            stderr=subprocess.DEVNULL if not getattr(args, "debug", False) else None,
            check=False,
        )
    finally:
        Path(concat_path).unlink(missing_ok=True)

    if proc.returncode != 0:
        print("Error: Failed to create video", flush=True)
        return 1

    print(f"✓ Video created: {output}")
    print(f'Play with: mpv --fs "{output}"')
    return 0
